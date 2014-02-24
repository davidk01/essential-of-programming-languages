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

    number = one_of(/\d/).many[:digits] >> ->(s) {
      [ConstExp.new(s[:digits].map(&:text).join.to_i)]
    }

    identifier = one_of(/[^\s\(\)\,;<{}\.\->]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    order_operator = ((m('<=') | m('>=') | one_of('<', '=', '>'))[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator].map(&:text).join]]
    }

    arithmetic_operator = (one_of('-', '+', '*', '/')[:operator] > cut!) >> ->(s) {
      [operator_class_mapping[s[:operator][0].text]]
    }

    general_arithmetic_operator = order_operator | arithmetic_operator

    unary_operator = (m('not') | m('neg'))[:op] >> ->(s) {
      [operator_class_mapping[s[:op].map(&:text).join]]
    }

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

    # x <- expression
    var_assignment = (identifier[:var] > ws > m('<-') > cut! > ws >
     r(:expression)[:expr] > ws > one_of(';')) >> ->(s) {
      [Assignment.new(s[:var][0], s[:expr][0])]
    }
    
    # { s* }
    statement_block = (one_of('{') > cut! > (ws > r(:statement)).many.any[:statements] >
     ws > one_of('}') > cut!) >> ->(s) {
      [StatementBlock.new(s[:statements])]
    }

    # if (e) { s+ } (else { s+ })?
    if_statement = (m('if') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] > ws >
     one_of(')') > cut! > ws > statement_block[:true_branch] >
     (ws > m('else') > cut! > ws > statement_block[:false_branch] > cut!).any) >> ->(s) {
      [If.new(s[:test][0], s[:true_branch][0], (false_branch = s[:false_branch]) ? 
       false_branch[0] : StatementBlock.new([]))]
    }

    # while (e) { s+ }
    while_statement = (m('while') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:test] >
     ws > one_of(')') > cut! > ws > statement_block[:body]) >> ->(s) {
      [While.new(s[:test][0], s[:body][0])]
    }

    # for (e1; e2; e3) { s+ }
    for_statement = (m('for') > cut! > ws > one_of('(') > cut! > ws > r(:expression)[:init] >
     one_of(';') > cut! > ws > r(:expression)[:test] > one_of(';') > cut! > ws >
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
     one_of(')') > ws > one_of('{') > (ws > case_fragment).many[:cases] > ws >
     m('default:') > cut! > ws > statement_block[:default]) >> ->(s) {
      [Switch.new(s[:test][0], s[:cases], s[:default][0])]
    }

    # int or name of a declared type
    basic_type = ((m('int') | m('float') | m('bool'))[:basic] | identifier[:derived]) >> ->(s) {
      [if s[:basic]
        case s[:basic].map(&:text).join
        when 'int'
          IntType
        when 'float'
          FloatType
        when 'bool'
          BoolType
        end
      else
        DerivedType.new(s[:derived][0])
      end]
    }

    # pointer type
    ptr_type = (m('ptr(') > cut! > ws > r(:type_expression)[:type] > ws > one_of(')') >
     cut!) >> ->(s) {
      [PtrType.new(s[:type][0])]
    }

    # array type
    array_type = (m('array(') > cut! > ws > r(:type_expression)[:type] > ws > one_of(',') >
     ws > number[:count] > ws > one_of(')')) >> ->(s) {
      [ArrayType.new(s[:type][0], s[:count][0])]
    }

    # general type expression
    rule :type_expression, ptr_type | array_type | basic_type

    # type variable; (force initialization to happen later for now)
    variable_declaration = (r(:type_expression)[:type] > ws > identifier[:variable] >
     ws > (one_of('=').ignore > cut! > ws > r(:expression)).any[:value] > one_of(';')) >> ->(s) {
      [VariableDeclaration.new(s[:type][0], s[:variable][0], s[:value][0])]
    }
    
    # function definition
    function_definition_argument = (r(:type_expression)[:type] > sep > identifier[:name]) >> ->(s) {
      [ArgumentDefinition.new(s[:type][0], s[:name][0])]
    }

    function_arguments = (function_definition_argument[:first] > (ws >
     one_of(',').ignore > cut! > function_definition_argument).many.any[:rest]) >> ->(s) {
      s[:first] + s[:rest]
    }
     
    function_definition = (r(:type_expression)[:return_type] > sep > identifier[:function_name] >
     ws > one_of('(') > cut! > function_arguments.any[:arguments] > one_of(')') > cut! > ws >
     statement_block[:function_body]) >> ->(s) {
      [FunctionDefinition.new(s[:return_type][0], s[:arguments], s[:function_body][0])]
    }

    # return statement
    return_statement = (m('return') > sep > r(:expression)[:return] > ws > one_of(';')) >> ->(s) {
      [ReturnStatement.new(s[:return][0])]
    }

    # all the statements
    rule :statement, function_definition | return_statement | if_statement | while_statement | 
     for_statement | switch_statement | variable_declaration | return_statement | var_assignment |
     (r(:expression) > one_of(';').ignore) | statement_block

    # expr; {expr;}*
    rule :statements, (r(:statement)[:first] > (ws > r(:statement)).many.any[:rest]) >> ->(s) {
      [Statements.new(s[:first] + s[:rest])]
    }
    
    # all the expressions
    rule :expression, arithmetic_expression | unary_expression | number | identifier

    rule :start, r(:statements)

  end

  def self.parse(iterable); @grammar.parse(iterable); end

end
