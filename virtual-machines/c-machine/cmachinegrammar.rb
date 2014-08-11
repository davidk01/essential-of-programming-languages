require 'pegrb'
require_relative './ast'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix/function style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
module CMachineGrammar

  @grammar = Grammar.rules do

    # There is a common structure to expressions of the form {op}(expr {, expr}+) so we
    # can map "op" to a class as soon as we see it.
    operator_class_mapping = {'-' => DiffExp, '+' => AddExp, '*' => MultExp, '/' => DivExp,
     '<' => LessExp, '<=' => LessEqExp, '=' => EqExp, '>' => GreaterExp, '>=' => GreaterEqExp,
     'not' => NotExp, 'neg' => NegExp}

    # Whitespace and separators.
    ws, sep = one_of(/\s/).many.any.ignore, one_of(/\s/).many.ignore

    # Numbers, e.g. 123, 123.544.
    number = (one_of(/\d/).many[:digits] > (one_of('.') > one_of(/\d/).many.any).any[:fraction]) >> ->(s) {
      Number.new(s[:digits].map(&:text).join.to_i + s[:fraction].map(&:text).join.to_f)
    }

    # Need to be careful with identifiers to not be overly restrictive but also to not eat up
    # other grammatical punctuations like type declarations, sequencing, function calls, etc.
    identifier = one_of(/[^\s\(\),;<{}\.\->:]/).many[:chars] >> ->(s) {
      Identifier.new(s[:chars].map(&:text).join)
    }

    # <=, <, =, >, >=
    order_operator = ((m('<=') | m('>=') | one_of('<', '=', '>'))[:operator] > cut!) >> ->(s) {
      operator_class_mapping[s[:operator].text]
    }

    # -, +, *, /
    arithmetic_operator = (one_of('-', '+', '*', '/')[:operator] > cut!) >> ->(s) {
      operator_class_mapping[s[:operator].text]
    }

    # comparison or arithmetic operator
    general_arithmetic_operator = order_operator | arithmetic_operator

    # negation and boolean not
    unary_operator = (m('not') | m('neg'))[:op] >> ->(s) {
      operator_class_mapping[s[:op].text]
    }

    # {not, neg}(expr)
    unary_expression = (unary_operator[:op] > one_of('(') > cut! > ws > r(:expression)[:expression] >
     ws > one_of(')') > cut!) >> ->(s) {
      s[:op].new(s[:expression])
    }

    # op(expr {, expr}+)
    arithmetic_expression = (general_arithmetic_operator[:op] > one_of('(') > ws > cut! >
     r(:expression)[:first] > (ws > one_of(',').ignore > ws > cut! > r(:expression)).many[:rest] >
     ws > one_of(')') > cut!) >> ->(s) {
      s[:op].new([s[:first]] + s[:rest].flatten)
    }

    # x = expression; (statement)
    var_assignment = (identifier[:var] > ws > m('=') > cut! > ws > r(:expression)[:expr]) >> ->(s) {
      Assignment.new(s[:var], s[:expr])
    }
    
    # { s* }
    statement_block = (one_of('{') > cut! > (ws > r(:statement)).many.any[:statements] >
     ws > one_of('}') > cut!) >> ->(s) {
      Statements.new(s[:statements].flatten)
    }

    # if (e) { s+ } (else { s+ })?
    if_statement = (m('if') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] > ws >
     one_of(')') > cut! > ws > statement_block[:true_branch] >
     (ws > m('else') > cut! > ws > statement_block[:false_branch] > cut!).any) >> ->(s) {
      If.new(s[:test], s[:true_branch], (false_branch = s[:false_branch]) ? 
       false_branch : Statements.new([]))
    }

    # while (e) { s+ }
    while_statement = (m('while') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] >
     ws > one_of(')') > cut! > ws > statement_block[:body]) >> ->(s) {
      While.new(s[:test], s[:body])
    }

    # need to wrap up an expression into a statement otherwise we are missing :pop operations
    # during compilation.
    expression_statement = (r(:expression) > ws > one_of(';').ignore)[:expression] >> ->(s) {
      ExpressionStatement.new(s[:expression].first)
    }

    # for (e1; e2; e3) { s+ }
    for_statement = (m('for') > cut! > ws > one_of('(') > ws > expression_statement[:init] >
     cut! > ws > expression_statement[:test] > cut! > ws >
     r(:expression)[:update] > ws > one_of(')') > ws > statement_block[:body]) >> ->(s) {
      For.new(s[:init], s[:test], s[:update], s[:body])
    }

    # e.g. case 1: { s+ }
    case_fragment = (m('case') > cut! > sep > number[:case] > one_of(':') > cut! > ws >
     statement_block[:body]) >> ->(s) {
      CaseFragment.new(s[:case], s[:body])
    }

    # switch (e) { case 0: { s+ } case 1: { s+ } ... default: { s+ } }
    switch_statement = (m('switch') > cut! > ws > one_of('(') > ws > r(:expression)[:test] > ws >
     one_of(')') > ws > one_of('{') > cut! > (ws > case_fragment).many[:cases] > ws >
     m('default:') > cut! > ws > statement_block[:default]) >> ->(s) {
      Switch.new(s[:test], s[:cases], s[:default])
    }

    # ;
    empty_statement = ws > one_of(';').ignore

    # Basic types (not an expression or a statement), e.g. int, float.
    basic_type_mapping = {'int' => IntType, 'float' => FloatType, 'bool' => BoolType, 'void' => VoidType}
    basic_type = ((m('int') | m('float') | m('bool'))[:basic] | identifier[:derived]) >> ->(s) {
      s[:basic] ? basic_type_mapping[s[:basic].text] : DerivedType.new(s[:derived])
    }

    # pointer type, e.g. ptr(int), ptr(float).
    ptr_type = (m('ptr(') > ws > r(:type_expression)[:type] > ws > one_of(')')) >> ->(s) {
      PtrType.new(s[:type])
    }

    # array type, e.g. array(int, 10), array(ptr(int), 10)
    array_type = (m('array(') > ws > r(:type_expression)[:type] > ws > one_of(',') >
     ws > number[:count] > ws > one_of(')')) >> ->(s) {
      ArrayType.new(s[:type], s[:count].to_i)
    }

    # type expression
    rule :type_expression, ptr_type | array_type | basic_type

    # typed variable declaration along with optional assignment (statement), e.g. int x, int x = 100.
    variable_declaration = (identifier[:variable] > ws > one_of(':') > ws > r(:type_expression)[:type] >
     ws > (one_of('=').ignore > cut! > ws > r(:expression)).any[:value] > one_of(';')) >> ->(s) {
      VariableDeclaration.new(s[:type], s[:variable], s[:value].first)
    }

    # type variable_name, e.g. var : type, x : ptr(int), x : array(int, 10)
    function_definition_argument = (identifier[:name] > ws > one_of(':') > ws > r(:type_expression)[:type]) >> ->(s) {
      ArgumentDefinition.new(s[:type], s[:name])
    }

    # type var1 {, type var2}*, e.g. (x : int, y : int, z : ptr(int))
    function_arguments = (function_definition_argument[:first] > (ws >
     one_of(',').ignore > cut! > function_definition_argument).many.any[:rest]) >> ->(s) {
      [s[:first]] + s[:rest]
    }

    # function_name({type arg}*) -> return_type { statments* } (statement), e.g. func(x : int, y : int) -> array(int, 2) { ... }
    function_definition = (identifier[:function_name] > ws > one_of('(') > function_arguments.any[:arguments] >
     one_of(')') > ws > m('->') > ws > r(:type_expression)[:return_type] > ws > statement_block[:function_body] >
     cut!) >> ->(s) {
      FunctionDefinition.new(s[:return_type], s[:function_name], s[:arguments], s[:function_body])
    }

    # arguments {expr,}*, e.g. (x, y, z, +(x, y))
    function_call_arguments = (r(:expression)[:first] > (ws > one_of(',').ignore > cut! >
     r(:expression)).many.any[:rest]) >> ->(s) {
      [s[:first]] + s[:rest]
    }

    # function_name({expressions}*), e.g. f(1, 2, 3, +(4, 5))
    function_call = (identifier[:function_name] > ws > one_of('(') > ws >
     function_call_arguments.any[:arguments] > ws > one_of(')') > cut!) >> ->(s) {
      FunctionCall.new(s[:function_name], s[:arguments])
    }

    # return statement, e.g. return x; return 1; return +(x, y);
    return_statement = (m('return') > sep > r(:expression)[:return] > ws > one_of(';')) >> ->(s) {
      ReturnStatement.new(s[:return])
    }

    # {var : type;}, e.g. xyz : ptr(int);
    struct_member = (identifier[:name] > ws > one_of(':') > ws > r(:type_expression)[:type] >
     ws > one_of(';')) >> ->(s) {
      StructMember.new(s[:type], s[:name])
    }

    # struct name { {var : type;}+ }, e.g. struct s { xyz : int; w : ptr(int); }
    struct_declaration = (m('struct') > cut! > sep > identifier[:name] > ws > one_of('{') >
     ws > (struct_member > ws > cut!).many[:members] > ws > one_of('}')) >> ->(s) {
      StructDeclaration.new(s[:name], s[:members].flatten)
    }

    # all the statements
    rule :statement, function_definition | return_statement | if_statement | while_statement | 
     for_statement | switch_statement | variable_declaration | struct_declaration |
     expression_statement | statement_block | empty_statement

    # expr; {expr;}*
    rule :statements, (r(:statement)[:first] > (ws > r(:statement)).many.any[:rest]) >> ->(s) {
      Statements.new([s[:first]] + s[:rest].flatten)
    }
    
    # all the expressions
    rule :expression, number | arithmetic_expression | unary_expression | function_call | var_assignment |
     identifier

    rule :start, r(:statements)

  end

  def self.parse(iterable); @grammar.parse(iterable); end

end
