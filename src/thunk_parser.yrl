%% Grammar of the Thunk language.
%%
%% The parser builds the nested lists the evaluator works on: a call
%% f(x, y) becomes [f, x, y], an operator becomes the call of its
%% primitive, and def, fn, let and if become the special forms
%% [def, ...], [lambda, ...], [let, ...] and [if, ...].
%%
%% A source is either a sequence of definitions (a program) or a single
%% expression.
%%
%% The bodies of fn, let and the else branch extend as far to the right
%% as possible: their keywords have the lowest precedence, so on a
%% conflict the parser keeps reading the body. Comparisons do not chain,
%% :: groups to the right, arithmetic to the left. Unary minus binds
%% tighter than any binary operator.

Nonterminals program defs definition names args expr call atom neg.
Terminals name int string def 'let' in 'if' then else fn true false
  '=' '->' '==' '<' '::' '+' '-' '*' '/' '%' '(' ')' '[' ']' ','.
Rootsymbol program.

Right    100 else in '->'.
Nonassoc 200 '<' '=='.
Right    300 '::'.
Left     400 '+' '-'.
Left     500 '*' '/' '%'.
Unary    600 neg.

program -> defs : '$1'.
program -> expr : ['$1'].

defs -> '$empty' : [].
defs -> definition defs : ['$1' | '$2'].

definition -> def name '=' expr : [def, value('$2'), '$4'].
definition -> def name '(' ')' '=' expr : [def, value('$2'), [lambda, [], '$6']].
definition -> def name '(' names ')' '=' expr : [def, value('$2'), [lambda, '$4', '$7']].

names -> name : [value('$1')].
names -> name ',' names : [value('$1') | '$3'].

args -> expr : ['$1'].
args -> expr ',' args : ['$1' | '$3'].

expr -> 'if' expr then expr else expr : ['if', '$2', '$4', '$6'].
expr -> 'let' name '=' expr in expr : ['let', value('$2'), '$4', '$6'].
expr -> fn '(' ')' '->' expr : [lambda, [], '$5'].
expr -> fn '(' names ')' '->' expr : [lambda, '$3', '$6'].
expr -> expr '<' expr : [lt, '$1', '$3'].
expr -> expr '==' expr : [eq, '$1', '$3'].
expr -> expr '::' expr : [cons, '$1', '$3'].
expr -> expr '+' expr : [add, '$1', '$3'].
expr -> expr '-' expr : [sub, '$1', '$3'].
expr -> expr '*' expr : [mul, '$1', '$3'].
expr -> expr '/' expr : ['div', '$1', '$3'].
expr -> expr '%' expr : [mod, '$1', '$3'].
expr -> neg expr : negate('$2').
expr -> call : '$1'.

neg -> '-' : '$1'.

call -> call '(' ')' : ['$1'].
call -> call '(' args ')' : ['$1' | '$3'].
call -> atom : '$1'.

atom -> name : value('$1').
atom -> int : value('$1').
atom -> string : value('$1').
atom -> true : true.
atom -> false : false.
atom -> '[' ']' : [].
atom -> '(' expr ')' : '$2'.

Erlang code.

value({_, _, Value}) -> Value.

%% A minus in front of a number is part of the number.
negate(N) when is_integer(N) -> -N;
negate(E) -> [sub, 0, E].
