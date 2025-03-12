(comment) @comment

(ident) @variable
((list . (expr(op )@function.call ) . (expr)*))

((ident) @function.builtin
	(#any-of?  @function.builtin "define" "lambda""begin" "quote""if" ))
((op) @operator
	(#any-of?  @operator "=" "+" "-" "/" "*"))
(list (expr(op(ident) @name)) 
	. (expr
	. (list . (expr(op(ident )@ignore )) . (expr)*))
	(#any-of? @name "lambda" "quote")
)

(list (expr(op(ident) @out)) . (expr  
(list  (expr(op(ident )@variable.parameter)) . (expr)*)
)
(#eq? @out "lambda")
)
(
	list . (expr ( op (ident ) @ignore)    (#eq? @ignore "define")
)
    . (expr (op (ident) @function)) 
    . (expr (list . (expr(op(ident) @out)(#eq? @out "lambda")))) 
)
(
	list . (expr ( op (ident ) @ignore)    (#eq? @ignore "define")
)
    . (expr (op (ident) @variable)) 
    . (expr )
)

(string) @string
"(" @punctuation.bracket
")" @punctuation.bracket
(number) @number
