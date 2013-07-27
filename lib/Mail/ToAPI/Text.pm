package Mail::ToAPI::Text;

use strict;
use 5.010;
our $VERSION = '0.1';

use parent qw/Exporter/;
use HTML::Parser;
use HTML::Entities;

our @EXPORT_OK = qw/_parse_for_text/;

sub _parse_for_text {
    my $email = shift;

    my $body_str;
    if ($email->content_type =~ m{text/html}) {
        $body_str = textify_html($email->body_str);
    }
    else {
        $body_str = $email->body_str;
    }

    $body_str =~ s/^\s+//s;
    $body_str =~ s/\s+\z//s;

    return $body_str;
}

*unescapeHTMLFull = \&HTML::Entities::decode_entities;

sub textify_html($) {
    my $p = new HTML::Parser
        api_version => 3,
        start_h     => [\&_textify_tag, 'self, tagname, skipped_text, attr'],
        end_h       => [\&_textify_end_tag, 'self, tagname, skipped_text'],
        end_document_h=> [ sub { $_[0]->{result} .= _textify_decode($_[1]) }, 'self, skipped_text'],
        process_h   => [""],
        declaration_h=> [""],
        comment_h   => [""];

    $p->{result} = '';
    $p->{inside_bad_element} = undef;

    $p->parse($_[0]); # html (first arg)
    $p->eof;

    $p->{result} =~ s/[ \n\r\t]*\n[ \n\r\t]*\n/\n\n/gs;

    $p->{result} =~ s/\s+\z/\n/s;

    return $p->{result};
}

sub _textify_tag {
    my ($p, $tag, $skipped, $attrs) = @_;

    return if $p->{inside_bad_element};

    $skipped =~ s/\s+/ /sg; # Multiple spaces,newlines in html is simple space
    $p->{result} .= _textify_decode($skipped);

    if ($tag eq 'script' || $tag eq 'style') {
        $p->{inside_bad_element} = $tag;
        return;
    }

    if ($tag eq 'br' || $tag eq 'p' || $tag eq 'div') {
        $p->{result} .= "\n" if $p->{result} ne q{};

    } elsif ($tag eq 'hr') {
        $p->{result} .= "\n" . '-' x 50 . "\n";

    } elsif ($tag eq 'a') {
        $p->{a_href} = $attrs->{href}; # Save href for comparison with text content
        $p->{a_href_start} = length($p->{result});
    }
}

sub _textify_end_tag {
    my ($p, $tag, $skipped) = @_;

    unless ($p->{inside_bad_element}) {
        $skipped =~ s/\s+/ /sg; # Multiple spaces,newlines in html is simple space
        $p->{result} .= _textify_decode($skipped);
    } elsif ($p->{inside_bad_element} eq $tag) {
        $p->{inside_bad_element} = undef
    }

    # '<a href="URL">here</a>' => 'here [URL]'
    if ($tag eq 'a' && $p->{a_href}) {
        my $href    = $p->{a_href};
        $href =~ s{^(?:
                http:// (?=www\.) |
                ftp://  (?=ftp\.) |
                mailto:
            ) }{}xi;
        $href =~ s{/$}{};

        if (substr($p->{result}, $p->{a_href_start}) !~ /\Q$href\E/i) { # Content not contail URL?
            $p->{result} .= (substr($p->{result}, -1) eq ' ' ? '' : ' ') .
                '[' . $p->{a_href} . ']';
        }
        undef $p->{a_href}, $p->{a_href_start};
    }
}

#   _textify_decode()
# Get: ($html_part)
# Return: $text
sub _textify_decode {
    my $t = unescapeHTMLFull($_[0]);
    $t =~ tr/\xA0/ /; # nbsp => space
    return $t;
}

1;
