use Cro::Uri :decode-percents, :encode-percents;
use Cro::HTTP::MultiValue;

class Cro::Uri::HTTP is Cro::Uri {
    has @!cached-query-list;
    has %!cached-query-hash;

    grammar Parser is Cro::Uri::GenericParser {
        proto token request-target { * }
        token request-target:sym<origin-form> {
            <absolute-path> [ "?" <query> ]?
        }

        token absolute-path {
            [ "/" <segment> ]+
        }
    }

    grammar Actions is Cro::Uri::GenericActions {
        method request-target:sym<origin-form>($/) {
            make Cro::Uri::HTTP.bless(
                path => $<absolute-path>.ast,
                |(query => .ast with $<query>)
            );
        }

        method absolute-path($/) {
            make ~$/;
        }
    }

    method parse-request-target(Str() $target) {
        with Parser.parse($target, :actions(Actions), :rule('request-target')) {
            .ast
        }
        else {
            die X::Cro::Uri::ParseError.new(uri-string => $target)
        }
    }

    method query-list() {
        # Race to compute this. The bind makes it thread-safe to put in place.
        unless @!cached-query-list {
            with self.query {
                @!cached-query-list := list eager .split('&').map: -> $kv {
                    my @kv := $kv.split('=', 2).list;
                    Pair.new:
                            key => decode-query-string-part(@kv[0]),
                            value => decode-query-string-part(@kv[1] // '')
                }
            }
        }
        @!cached-query-list
    }

    method query-hash() {
        # Race to compute this. The bind at the end makes it thread-safe to
        # put it in place, as opposed to an assignment which would not be.
        unless %!cached-query-hash {
            my %query-hash;
            with self.query {
                for .split('&') -> $kv {
                    my @kv := $kv.split('=', 2).list;
                    my $key = decode-query-string-part(@kv[0]);
                    my $value = decode-query-string-part(@kv[1] // '');
                    with %query-hash{$key} -> $existing {
                        %query-hash{$key} = Cro::HTTP::MultiValue.new(
                            $existing ~~ Cro::HTTP::MultiValue
                                ?? $existing.Slip
                                !! $existing,
                            $value
                        );
                    }
                    else {
                        %query-hash{$key} = $value;
                    }
                }
            }
            %!cached-query-hash := %query-hash;
        }
        %!cached-query-hash
    }

    #| Encodes the specified query string parameters and returns a new URI that incorporates
    #| them. Any existing query string parameters will be retained.
    method add-query(*@pairs, *%named-paris) {
        my @parts;
        if self.query -> $existing {
            @parts.push($existing);
        }
        for flat @pairs, %named-paris.pairs {
            @parts.push(encode-percents(.key.Str) ~ '=' ~ encode-percents(.value.Str));
        }
        self.add('?' ~ @parts.join("&"))
    }
}

#| Decodes a query string part. This involves replacing any +
#| characters with spaces, followed by the standard URI decoding
#| algorithm.
sub decode-query-string-part(Str $part --> Str) is export(:decode-query-string-part) {
    decode-percents $part.subst('+', ' ', :g)
}
