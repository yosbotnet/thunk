%% Tokens of the Thunk language.
%%
%% Keywords come before names: when both match the same text, leex picks
%% the rule written first. Otherwise the longest match wins, so "==" is
%% one token and "insert" is a name, not the keyword "in".

Definitions.

D = [0-9]
N = [a-z_][a-zA-Z0-9_]*\??
W = [\s\t\r\n]

Rules.

def|let|in|if|then|else|fn|true|false :
  {token, {list_to_atom(TokenChars), TokenLoc}}.
{N} :
  {token, {name, TokenLoc, list_to_atom(TokenChars)}}.
{D}+ :
  {token, {int, TokenLoc, list_to_integer(TokenChars)}}.
"([^"\\]|\\.)*" :
  string_token(TokenChars, TokenLoc).
"([^"\\]|\\.)* :
  {error, "unterminated string"}.
==|->|:: :
  {token, {list_to_atom(TokenChars), TokenLoc}}.
[-+*/%<=(),\[\]] :
  {token, {list_to_atom(TokenChars), TokenLoc}}.
#[^\n]* :
  skip_token.
{W}+ :
  skip_token.

Erlang code.

string_token(Chars, Loc) ->
    Inner = lists:sublist(Chars, 2, length(Chars) - 2),
    case unescape(Inner, []) of
        {ok, S} -> {token, {string, Loc, unicode:characters_to_binary(S)}};
        error -> {error, "invalid escape"}
    end.

unescape([], Acc) -> {ok, lists:reverse(Acc)};
unescape([$\\, $n | T], Acc) -> unescape(T, [$\n | Acc]);
unescape([$\\, $t | T], Acc) -> unescape(T, [$\t | Acc]);
unescape([$\\, $" | T], Acc) -> unescape(T, [$" | Acc]);
unescape([$\\, $\\ | T], Acc) -> unescape(T, [$\\ | Acc]);
unescape([$\\ | _], _Acc) -> error;
unescape([C | T], Acc) -> unescape(T, [C | Acc]).
