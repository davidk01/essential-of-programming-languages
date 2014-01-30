require 'bundler/setup'
require 'pegrb'

module TestCases

end

module LetGrammar

  class ConstExp < Struct.new(:value); end
  class DiffExp < Struct.new(:expressions); end
  class ZeroCheck < Struct.new(:expressions); end
  class IfExp < Struct.new(:test, :true, :false); end
  class Identifier < Struct.new(:value); end
  class LetExpression < Struct.new(:variable, :value, :body); end

  @grammar = Grammar.rules do

    whitespace = one_of(/\s/).many.any.ignore

    sep = one_of(/\s/).many.ignore

    number = (one_of(/\d/).many[:digits] > cut!) >> ->(s) {
      [ConstExp.new(s[:digits].map(&:text).join.to_i)]
    }

    # -(expression {, expression}+)
    difference = (m('-(') > whitespace > cut! > r(:expression)[:first] >
     (whitespace > one_of(',').ignore > whitespace > cut! > r(:expression)).many[:rest] >
     whitespace > one_of(')') > cut!) >> ->(s) {
       [DiffExp.new(s[:first] + s[:rest])]
    }

    # zero?(expression {, expression}+)
    zero_check = (m('zero?(') > whitespace > cut! > r(:expression)[:first] >
     (whitespace > one_of(',').ignore > whitespace > cut! > r(:expression)).many.any[:rest] >
     whitespace > one_of(')') > cut!) >> ->(s) {
       [ZeroCheck.new(s[:first] + s[:rest])]
    }

    # if expression then expression else expression
    if_expression = (m('if') > sep > cut! > whitespace > r(:expression)[:test] > sep >
     m('then') > sep > cut! > r(:expression)[:true] > sep >
     m('else') > sep > cut! > r(:expression)[:false] > cut!) >> ->(s) {
      [IfExp.new(s[:test][0], s[:true][0], s[:false][0])]
    }

    identifier = one_of(/[^\s\(\)]/).many[:chars] >> ->(s) {
      [Identifier.new(s[:chars].map(&:text).join)]
    }

    # let identifier = expression in expression
    let_expression = (m('let') > sep > cut! > identifier[:variable] > sep >
     one_of('=') > sep > cut! > r(:expression)[:value] > sep >
     m('in') > sep > cut! > r(:expression)[:body] > cut!) >> ->(s) {
      [LetExpression.new(s[:variable][0], s[:value][0], s[:body][0])]
    }

    # all the expression together
    rule :expression, number | difference | zero_check |
     if_expression | let_expression | identifier

    rule :start, r(:expression)

  end

  def self.parse(indexable); @grammar.parse(indexable); end

end
