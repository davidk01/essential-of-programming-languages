require 'pegrb'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix/function style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
module CMachineGrammar

  # AST classes
  class Identifier < Struct.new(:value); end
  class ConstExp < Struct.new(:value); end
  class DiffExp < Struct.new(:expressions); end
  class AddExp < Struct.new(:expressions); end
  class MultExp < Struct.new(:expressions); end
  class DivExp < Struct.new(:expressions); end
  class LessExp < Struct.new(:expressions); end
  class LessEqExp < Struct.new(:expressions); end
  class EqExp < Struct.new(:expressions); end
  class GreaterExp < Struct.new(:expressions); end
  class GreaterEqExp < Struct.new(:expressions); end
  class NotExp < Struct.new(:expression); end
  class NegExp < Struct.new(:expression); end
  class Assignment < Struct.new(:left, :right); end
  class If < Struct.new(:test, :true_branch, :false_branch); end
  class While < Struct.new(:test, :body); end
  class For < Struct.new(:init, :test, :update, :body); end
  class CaseFragment < Struct.new(:case, :body); end
  class Switch < Struct.new(:test, :cases, :default); end
  class StatementBlock < Struct.new(:statements); end 
  class Statements < Struct.new(:statements); end

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

    identifier = one_of(/[^\s\(\)\,;<{}]/).many[:chars] >> ->(s) {
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
    assignment = (identifier[:var] > sep > m('<-') > cut! > ws >
     r(:expression)[:expr]) >> ->(s) {
      [Assignment.new(s[:var][0], s[:expr][0])]
    }
    
    # { s* }
    statement_block = (one_of('{') > cut! > (ws > r(:statement)).many.any[:statements] >
     one_of('}') > cut!) >> ->(s) {
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
     m('default:') > ws > statement_block[:default]) >> ->(s) {
      [Switch.new(s[:test][0], s[:cases], s[:default][0])]
    }

    #
    rule :statement, if_statement | while_statement | for_statement | switch_statement |
     (r(:expression) > one_of(';').ignore) | statement_block

    statement_block = (one_of('{') > cut! > (sep > r(:statement)).many.any[:statements] >
     one_of('}')) >> ->(s) {
      [StatementBlock.new(s[:statements])]
    }

    # expr; {expr;}*
    rule :statements, (r(:statement)[:first] > (sep > r(:statement)).many.any[:rest]) >> ->(s) {
      [Statements.new(s[:first] + s[:rest])]
    }
    
    # all the expressions
    rule :expression, arithmetic_expression | unary_expression | assignment | number | identifier

    rule :start, r(:statements)

  end

  def self.parse(iterable); @grammar.parse(iterable); end

end
