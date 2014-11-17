require 'pegrb'
require_relative './ast'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix/function style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
module CMachineGrammar

  @grammar = Grammar.rules do

    ws = one_of(/\s/).many.any.ignore

    lpar, rpar = one_of('(').ignore, one_of(')').ignore

    comment = (m(';;') > one_of(/[^\s]/).many.any > one_of(/\s/).many).ignore

    symbol = (one_of(/[^\(\)\;]/)[:first] > one_of(/[^\s\(\)]/).many.any[:rest]) >> ->(s) {
      [s[:first], s[:rest]].flatten.map(&:text).join.to_sym
    }

    integer = one_of(/\d/).many[:digits] >> ->(s) {
      s[:digits].map(&:text).join.to_i
    }

    boolean = (m('#t')[:true] | m('#f')[:false]) >> ->(s) {
      s[:true] ? true : false
    }

    float = (one_of(/\d/).many[:integral] > one_of('.') > one_of(/\d/).many[:fractional]) >> ->(s) {
      [s[:integral].map(&:text), '.', s[:fractional].map(&:text)].flatten.join.to_f
    }

    atomic = float | integer | boolean | symbol

    empty_list = lpar > ws > rpar

    non_empty_list = (lpar > (ws > (atomic | r(:list))).many[:elements] > ws > rpar) >> ->(s) {
      s[:elements].map(&:first)
    }

    rule :list, non_empty_list | empty_list

    program = (ws > (comment | r(:list)) > ws).many

    rule :start, program
  end

  def self.parse(iterable); @grammar.parse(iterable); end

end
