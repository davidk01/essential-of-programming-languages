require 'pegrb'
require './ast'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix/function style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
module CMachineGrammar

  @grammar = Grammar.rules do

    # There is a common structure to expression of the form {op}(expr {, expr}+) so we
    # can map "op" to a class as soon as we see it.
    operator_class_mapping = {'-' => DiffExp, '+' => AddExp, '*' => MultExp, '/' => DivExp,
     '<' => LessExp, '<=' => LessEqExp, '=' => EqExp, '>' => GreaterExp, '>=' => GreaterEqExp,
     'not' => NotExp, 'neg' => NegExp
    }

    ws, sep = one_of(/\s/).many.any.ignore, one_of(/\s/).many.ignore

    # just integers for the time being
    number = (one_of(/\d/).many[:digits] > (one_of('.') > one_of(/\d/).many.any).any[:fraction]) >> ->(s) {
      [ConstExp.new(s[:digits].map(&:text).join.to_i + s[:fraction].map(&:text).join.to_f)]
    }

    # careful with punctuation
    identifier = one_of(/[^\s\(\),;<{}\.\->:]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    # <=, <, =, >, >=
    order_operator = ((m('<=') | m('>=') | one_of('<', '=', '>'))[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].map(&:text).join]]
    }

    # -, +, *, /
    arithmetic_operator = (one_of('-', '+', '*', '/')[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator][0].text]]
    }

    # comparison or arithmetic operator
    general_arithmetic_operator = order_operator | arithmetic_operator

    # negation and boolean not
    unary_operator = (m('not') | m('neg'))[:op] >> ->(s) {
      [operator_class_mapping[s[:op].map(&:text).join]]
    }

    # {not, neg}(expr)
    unary_expression = (unary_operator[:op] > one_of('(') > cut! > ws >
        r(:expression)[:expression] > ws > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:expression][0])]
    }

    # op(expr {, expr}+)
    arithmetic_expression = (general_arithmetic_operator[:op] > one_of('(') > ws > cut! >
        r(:expression)[:first] > (ws > one_of(',').ignore > ws > cut! > r(:expression)).many[:rest] >
        ws > one_of(')') > cut!) >> ->(s) {
      [s[:op][0].new(s[:first] + s[:rest])]
    }

    # x = expression; (statement)
    var_assignment = (identifier[:var] > ws > m('=') > cut! > ws >
     r(:expression)[:expr]) >> ->(s) {
      [Assignment.new(s[:var][0], s[:expr][0])]
    }
    
    # { s* }
    statement_block = (one_of('{') > cut! > (ws > r(:statement)).many.any[:statements] >
     ws > one_of('}') > cut!) >> ->(s) {
      [Statements.new(s[:statements])]
    }

    # if (e) { s+ } (else { s+ })?
    if_statement = (m('if') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] > ws >
     one_of(')') > cut! > ws > statement_block[:true_branch] >
     (ws > m('else') > cut! > ws > statement_block[:false_branch] > cut!).any) >> ->(s) {
      [If.new(s[:test][0], s[:true_branch][0], (false_branch = s[:false_branch]) ? 
       false_branch[0] : Statements.new([]))]
    }

    # while (e) { s+ }
    while_statement = (m('while') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] >
     ws > one_of(')') > cut! > ws > statement_block[:body]) >> ->(s) {
      [While.new(s[:test][0], s[:body][0])]
    }

    # need to wrap up an expression into a statement otherwise we are missing :pop operations
    # during compilation.
    expression_statement = (r(:expression) > ws > one_of(';').ignore)[:expression] >> ->(s) {
      [ExpressionStatement.new(s[:expression][0])]
    }

    # for (e1; e2; e3) { s+ }
    for_statement = (m('for') > cut! > ws > one_of('(') > ws > expression_statement[:init] >
     cut! > ws > expression_statement[:test] > cut! > ws >
     r(:expression)[:update] > ws > one_of(')') > ws > statement_block[:body]) >> ->(s) {
      [For.new(s[:init][0], s[:test][0], s[:update][0], s[:body][0])]
    }

    # e.g. case 1: { s+ }
    case_fragment = (m('case') > cut! > sep > number[:case] > one_of(':') > cut! > ws >
     statement_block[:body]) >> ->(s) {
      [CaseFragment.new(s[:case][0], s[:body][0])]
    }

    # switch (e) { case 0: { s+ } case 1: { s+ } ... default: { s+ } }
    switch_statement = (m('switch') > cut! > ws > one_of('(') > ws > r(:expression)[:test] > ws >
     one_of(')') > ws > one_of('{') > cut! > (ws > case_fragment).many[:cases] > ws >
     m('default:') > cut! > ws > statement_block[:default]) >> ->(s) {
      [Switch.new(s[:test][0], s[:cases], s[:default][0])]
    }

    # ;
    empty_statement = ws > one_of(';').ignore

    # int or name of a declared type (not an expression or a statement)
    basic_type = ((m('int') | m('float') | m('bool'))[:basic] | identifier[:derived]) >> ->(s) {
      [if s[:basic]
        case s[:basic].map(&:text).join
        when 'int'
          IntType
        when 'float'
          FloatType
        when 'bool'
          BoolType
        when 'void'
          VoidType
        end
      else
        DerivedType.new(s[:derived][0])
      end]
    }

    # pointer type
    ptr_type = (m('ptr(') > ws > r(:type_expression)[:type] > ws > one_of(')')) >> ->(s) {
      [PtrType.new(s[:type][0])]
    }

    # array type
    array_type = (m('array(') > ws > r(:type_expression)[:type] > ws > one_of(',') >
     ws > number[:count] > ws > one_of(')')) >> ->(s) {
      [ArrayType.new(s[:type][0], s[:count][0])]
    }

    # type expression
    rule :type_expression, ptr_type | array_type | basic_type

    # typed variable declaration along with optional assignment (statement)
    variable_declaration = (identifier[:variable] > ws > one_of(':') > ws > r(:type_expression)[:type] >
     ws > (one_of('=').ignore > cut! > ws > r(:expression)).any[:value] > one_of(';')) >> ->(s) {
      [VariableDeclaration.new(s[:type][0], s[:variable][0], s[:value][0])]
    }
    
    # function definition components

    # type variable_name
    function_definition_argument = (identifier[:name] > ws > one_of(':') > ws > r(:type_expression)[:type]) >> ->(s) {
      [ArgumentDefinition.new(s[:type][0], s[:name][0])]
    }

    # type var1 {, type var2}*
    function_arguments = (function_definition_argument[:first] > (ws >
     one_of(',').ignore > cut! > function_definition_argument).many.any[:rest]) >> ->(s) {
      s[:first] + s[:rest]
    }

    # function_name({type arg}*) -> return_type { statments* } (statement)
    function_definition = (identifier[:function_name] > ws > one_of('(') > function_arguments.any[:arguments] >
     one_of(')') > ws > m('->') > ws > r(:type_expression)[:return_type] > ws > statement_block[:function_body] >
     cut!) >> ->(s) {
      [FunctionDefinition.new(s[:return_type][0], s[:function_name][0],
       s[:arguments], s[:function_body][0])]
    }

    # function call components

    # arguments {expr,}*
    function_call_arguments = (r(:expression)[:first] > (ws > one_of(',').ignore > cut! >
     r(:expression)).many.any[:rest]) >> ->(s) {
      s[:first] + s[:rest]
    }

    # function_name({expressions}*)
    function_call = (identifier[:function_name] > ws > one_of('(') > ws >
     function_call_arguments.any[:arguments] > ws > one_of(')') > cut!) >> ->(s) {
      [FunctionCall.new(s[:function_name][0], s[:arguments])]
    }

    # return statement
    return_statement = (m('return') > sep > r(:expression)[:return] > ws > one_of(';')) >> ->(s) {
      [ReturnStatement.new(s[:return][0])]
    }

    # {var : type;}
    struct_member = (identifier[:name] > ws > one_of(':') > ws > r(:type_expression)[:type] >
     ws > one_of(';')) >> ->(s) {
      [StructMember.new(s[:type][0], s[:name][0])]
    }

    # struct name { {var : type;}+ }
    struct_declaration = (m('struct') > cut! > sep > identifier[:name] > ws > one_of('{') >
     ws > (struct_member > ws > cut!).many[:members] > ws > one_of('}')) >> ->(s) {
      [StructDeclaration.new(s[:name][0], s[:members])]
    }

    # all the statements
    rule :statement, function_definition | return_statement | if_statement | while_statement | 
     for_statement | switch_statement | variable_declaration | struct_declaration |
     expression_statement | statement_block | empty_statement

    # expr; {expr;}*
    rule :statements, (r(:statement)[:first] > (ws > r(:statement)).many.any[:rest]) >> ->(s) {
      [Statements.new(s[:first] + s[:rest])]
    }
    
    # all the expressions
    rule :expression, arithmetic_expression | unary_expression | number | function_call | var_assignment |
     identifier

    rule :start, r(:statements)

  end

  def self.parse(iterable); @grammar.parse(iterable); end

end
