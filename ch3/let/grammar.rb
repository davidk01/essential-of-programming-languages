require 'pegrb'
require_relative './ast'

module LetGrammar

  def self.arithmetic_op_class_map
    @bin_op_map ||= {'-' => Diff, '+' => Add, '*' => Mult, '/' => Div,
     '=' => EqualTo, '>' => GreaterThan, '<' => LessThan}
  end

  def self.unary_op_class_map
    @unary_op_map ||= {'minus' => Minus, 'zero?' => Zero}
  end

  def self.list_op_class_map
    @list_op_map ||= {'car' => Car, 'cdr' => Cdr, 'null?' => Null}
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
    rule :expression, r(:arithmetic_expression) | r(:unary_arithmetic_expression) | r(:if) |
     r(:let) | r(:list) | r(:list_operation) | r(:list_constructor) | r(:cond) | basic_expr

    # TODO: test this
    test_result_expr = (r(:expression)[:test] > m(' ==> ') >
     r(:expression)[:value]) >> ->(s) {
      [{:test => s[:test][0], :value => s[:value][0]}]
    }
    rule :cond, (m('cond') > ws > cut! > test_result_expr.many.any[:conds]) >> ->(s) {
      [Cond.new(s[:conds])]
    }

    # emptylist or cons(expression, r(:list))
    emptylist = m('emptylist') >> ->(s) {
      [List.new([])]
    }
    non_empty_list = (m('cons(') > cut! > r(:expression)[:head] > (one_of(',').ignore > ws >
     r(:list)).many.any[:tail] > one_of(')')) >> ->(s) {
      [List.new(s[:head] + s[:tail])]
    }
    rule :list, emptylist | non_empty_list

    # list constructor
    rule :list_constructor, (m('list(') > cut! > r(:expression)[:first] >
     (one_of(',').ignore > ws > r(:expression)).many.any[:rest]) >> ->(s) {
      [List.new(s[:first] + s[:rest])]
    }

    # car, cdr, null?
    list_operator = (m('car') | m('cdr') | m('null?'))[:op] >> ->(s) {
      [s[:op].map(&:text).join]
    }
    rule :list_operation, (list_operator[:op] > one_of('(') > cut! > r(:list)[:list] >
     one_of(')')) >> ->(s) {
      [LetGrammar::list_op_class_map[s[:op].first].new(s[:list].first)]
    }

    # op(expr, expr), op(expr,     expr), op(expr,   \n\t\n\r\n expr), etc.
    rule :arithmetic_expression, (one_of(/[\-\+\*\/\=\>\<]/)[:op] > cut! > one_of('(') >
     r(:expression)[:first] > m(',') > ws > r(:expression)[:second] >
     one_of(')')) >> ->(s) {
      [LetGrammar::arithmetic_op_class_map[s[:op][0].text].new(*(s[:first] + s[:second]))]
    }

    # minus(expr), zero?(expr)
    unary_operator = (m('minus') | m('zero?'))[:op] >> ->(s) {
      [s[:op].map(&:text).join]
    }
    rule :unary_arithmetic_expression, (unary_operator[:op] > one_of('(') > cut! >
     r(:expression)[:expr] > one_of(')')) >> ->(s) {
      [LetGrammar::unary_op_class_map[[:op].first].new(s[:expr].first)]
    }

    # if expr (ws) then expr (ws) else expr 
    rule :if, (m('if') > ws > cut! > r(:expression)[:test] > ws > m('then') > ws >
     (r(:expression))[:then] > ws > m('else') > ws > (r(:expression))[:else]) >> ->(s) {
      [If.new(*(s[:test] + s[:then] + s[:else]))]
    }

    # let var = expr (ws) in (ws) expr
    rule :let, (m('let') > cut! > ws > ident[:var] > m(' = ') > r(:expression)[:value] > ws >
     m('in') > ws > r(:expression)[:body]) >> ->(s) {
      [Let.new(*(s[:var] + s[:value] + s[:body]))]
    }
  end

  def self.parse(string); @grammar.parse(string); end

end
