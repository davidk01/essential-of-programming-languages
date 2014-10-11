require 'pegrb'

module FunctionGrammar

  @grammar = Grammar.rules do

    ws = one_of(/\s/).many.ignore 

    atom = one_of(/[^\s\(\)\']/).many[:atom] >> ->(s) {
      case (a = s[:atom].map(&:text).join)
      when /^\d+$/
        a.to_i
      when /^#t$/
        true
      when /^#f$/
        false
      else
        a.to_sym
      end
    }

    comment = (m(';;') > cut! > one_of(/[^\n]/).many.any > one_of(/\n/)).ignore

    empty_list = (one_of('(') > ws.any > one_of(')')) >> ->(s) {
      []
    }

    list = (one_of('(') > cut! > ws.any > r(:expression)[:head] >
     (ws > r(:expression)).many.any[:tail] > ws.any > one_of(')')) >> ->(s) {
      [s[:head]] + s[:tail].map {|x| x.first}
    }

    quoted_expression = (one_of("'") > cut! > r(:expression)[:expr]) >> ->(s) {
      [:quote, s[:expr]]
    }

    line = ws.any > (comment | r(:expression)) > ws.any

    rule :expression, atom | empty_list | list | quoted_expression

    rule :start, line.many[:lines] >> ->(s) {
      s[:lines].map(&:first)
    }

  end

  def self.parse(string)
    @grammar.parse(string)
  end

end
