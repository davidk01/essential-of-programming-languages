require 'pegrb'
require_relative './ast'

module LetGrammar

  ##
  # Various maps that take a string and map it to the AST node class.

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

  ##
  # The actual grammar. Could use some cleanup.

  @grammar = Grammar.rules do
    rule :start, r(:expression)

    # whitespace
    space, newline = one_of(' ', "\t"), one_of("\n", "\r")
    ws = (space | newline).many.ignore

    # basic expressions: number, identifier, etc.
    num = one_of(/[0-9]/).many[:num] >> ->(s) {
      [Const.new(s[:num].map(&:text).join.to_i)]
    }
    ident = one_of(/[a-zA-Z]/).many[:ident] >> ->(s) {
      [Var.new(s[:ident].map(&:text).join)]
    }
    basic_expr = num | ident

    # non-basic expressions
    rule :expression, r(:arithmetic_expression) | r(:unary_arithmetic_expression) | r(:if) |
     r(:let) | r(:list) | r(:list_operation) | r(:list_constructor) | r(:cond) |
     r(:unpack) | basic_expr

    # conditional expression "cond test ===> value, test2 ==> value2, ...", etc.
    test_result_expr = (r(:expression)[:test] > m(' ==> ') >
     r(:expression)[:value]) >> ->(s) {
      [{:test => s[:test].first, :value => s[:value].first}]
    }
    rule :cond, (m('cond') > cut! > ws > test_result_expr[:first] >
     (m(',') > ws > test_result_expr).many.any[:rest]) >> ->(s) {
      [Conds.new(s[:first] + s[:rest])]
    }

    # emptylist or cons(expression, r(:conslist)), all expression should refer to :list
    emptylist = m('emptylist').ignore
    cons = (m('cons(') > cut! > r(:expression)[:head] > (one_of(',').ignore > ws >
     r(:conslist)).many.any[:tail] > one_of(')')) >> ->(s) {
      [Cons.new(s[:head], s[:tail].first || [])]
    }
    rule :conslist, emptylist | cons
    rule :list, r(:conslist)[:constree] >> ->(s) {
      [List.new(s[:constree].first.flatten)]
    }

    # list constructor
    rule :list_constructor, (m('list(') > cut! > r(:expression)[:first] >
     (one_of(',').ignore > ws > r(:expression)).many.any[:rest] > one_of(')')) >> ->(s) {
      [List.new(s[:first] + s[:rest])]
    }

    # car, cdr, null?
    list_operator = (m('car') | m('cdr') | m('null?'))[:op] >> ->(s) {
      [s[:op].map(&:text).join]
    }
    rule :list_operation, (list_operator[:op] > cut! > one_of('(') > r(:expression)[:list] >
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
      [LetGrammar::unary_op_class_map[s[:op].first].new(s[:expr].first)]
    }

    # if expr (ws) then expr (ws) else expr 
    rule :if, (m('if') > ws > cut! > r(:expression)[:test] > ws > m('then') > ws >
     (r(:expression))[:then] > ws > m('else') > ws > (r(:expression))[:else]) >> ->(s) {
      [If.new(*(s[:test] + s[:then] + s[:else]))]
    }

    # let var = expr (ws) in (ws) expr
    single_let_expr = (ident[:var] > m(' = ') > cut! > r(:expression)[:value]) >> ->(s) {
      [LetBinding.new(s[:var].first, s[:value].first)]
    }
    multiple_let_bindings = (single_let_expr[:first] > (one_of(',').ignore > ws >
     single_let_expr).many.any[:rest]) >> ->(s) {
      s[:first] + s[:rest]
    }
    rule :let, (m('let') > cut! > ws > multiple_let_bindings[:bindings] > ws >
     m('in') > ws > r(:expression)[:body]) >> ->(s) {
      [Let.new(s[:bindings], s[:body][0])]
    }

    # unpack x, y, z = list(1, 2, 3) maps to x = 1, y = 2, z = 3
    ident_list = (ident[:first] > (one_of(',').ignore > cut! > ws >
     ident).many.any[:rest]) >> ->(s) {
      s[:first] + s[:rest]
    }
    rule :unpack, (m('unpack') > cut! > ws > ident_list[:idents] > m(' = ') >
     r(:expression)[:packed] > ws > m('in') > ws > r(:expression)[:body]) >> ->(s) {
      [Unpack.new(s[:idents], s[:packed].first, s[:body].first)]
    }
  end

  def self.parse(string); @grammar.parse(string); end

end
