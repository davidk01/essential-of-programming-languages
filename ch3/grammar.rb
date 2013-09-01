require 'pegrb'
require_relative './ast'

module LetGrammar

  @grammar = Grammar.rules do
    rule :start, r(:expression)

    # basic expressions
    num = one_of(/[0-9]/).many[:num] >> ->(s) {
      [ConstExpr.new(s[:num].map(&:text).join.to_i)]
    }
    ident = one_of(/[a-zA-Z]/).many[:ident] >> ->(s) {
      [VarExpr.new(s[:ident].map(&:text).join)]
    }
    basic_expr = num | ident

    # non-basic expressions
    rule :expression, r(:diff) | r(:zero?) | r(:if) | r(:let) | basic_expr

    # -(expr, expr)
    rule :diff, (m('-(') > (basic_expr | r(:diff) | r(:if) | r(:let))[:first] >
     m(', ') > (basic_expr | r(:diff) | r(:if) | r(:let))[:second] > m(')')) >> ->(s) {
      [DiffExpr.new(*(s[:first] + s[:second]))]
    }

    # zero? (expr)
    rule :zero?, (m('zero? (') > (basic_expr | r(:diff) | r(:if) |
     r(:let))[:expr] > m(')')) >> ->(s) {
      [ZeroExpr.new(s[:expr].first)]
    }

    # if expr then expr else expr 
    rule :if, (m('if ') > (r(:diff) | r(:zero?) | r(:if) | r(:let) | ident)[:test] >
     m(' then ') > (r(:expression))[:then] > m(' else ') > (r(:expression))[:else]) >> ->(s) {
      [IfExpr.new(*(s[:test] + s[:then] + s[:else]))]
    }

    # let var = expr in expr
    rule :let, (m('let ') > ident[:var] > m(' = ') > r(:expression)[:value] >
     m(' in ') > r(:expression)[:body]) >> ->(s) {
      [LetExpr.new(*(s[:var] + s[:value] + s[:body]))]
    }
  end

  def self.parse(string); @grammar.parse(string); end

end
