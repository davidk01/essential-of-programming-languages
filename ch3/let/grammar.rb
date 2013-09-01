require 'pegrb'
require_relative './ast'

module LetGrammar

  def self.arithmetic_class_map
    @map ||= {'-' => Diff, '+' => Add, '*' => Mult, '/' => Div,
     '=' => EqualTo, '>' => GreaterThan, '<' => LessThan}
  end

  @grammar = Grammar.rules do
    rule :start, r(:expression)

    space, newline = one_of(' ', "\t"), one_of("\n", "\r")
    ws = (space | newline).many.ignore

    # basic expressions
    num = one_of(/[0-9]/).many[:num] >> ->(s) {
      [Const.new(s[:num].map(&:text).join.to_i)]
    }
    ident = one_of(/[a-zA-Z]/).many[:ident] >> ->(s) {
      [Var.new(s[:ident].map(&:text).join)]
    }
    basic_expr = num | ident

    # non-basic expressions
    rule :expression, r(:arithmetic_expression) | r(:minus) | r(:zero?) | r(:if) |
     r(:let) | basic_expr

    # op(expr, expr), op(expr,     expr), op(expr,   \n\t\n\r\n expr), etc.
    rule :arithmetic_expression, (one_of(/[\-\+\*\/\=\>\<]/)[:op] > one_of('(') >
     r(:expression)[:first] > m(',') > ws > r(:expression)[:second] >
     one_of(')')) >> ->(s) {
      [LetGrammar::arithmetic_class_map[s[:op][0].text].new(*(s[:first] + s[:second]))]
    }

    # minus(expr)
    rule :minus, (m('minus(') > r(:expression)[:expr] > one_of(')')) >> ->(s) {
      [Minus.new(s[:expr].first)]
    }

    # zero?(expr)
    rule :zero?, (m('zero?(') > r(:expression)[:expr] > m(')')) >> ->(s) {
      [Zero.new(s[:expr].first)]
    }

    # if expr (ws) then expr (ws) else expr 
    rule :if, (m('if ') > r(:expression)[:test] > ws > m('then ') >
     (r(:expression))[:then] > ws > m('else ') > (r(:expression))[:else]) >> ->(s) {
      [If.new(*(s[:test] + s[:then] + s[:else]))]
    }

    # let var = expr (ws) in (ws) expr
    rule :let, (m('let ') > ident[:var] > m(' = ') > r(:expression)[:value] > ws >
     m('in') > ws > r(:expression)[:body]) >> ->(s) {
      [Let.new(*(s[:var] + s[:value] + s[:body]))]
    }
  end

  def self.parse(string); @grammar.parse(string); end

end
