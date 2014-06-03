require 'bundler/setup'
require 'pegrb'

class ToyLang

  @grammar = Grammar.rules do
    # basic terms

    ws = one_of(/\s/).many.any.ignore

    variable = one_of(/[a-zA-Z]/).many[:chars] >> ->(s) {
      s[:chars].map(&:text).join
    }

    integer = one_of(/[0-9]/).many[:digits] >> ->(s) {
      s[:digits].map(&:text).join.to_i
    }

    basic = integer | r(:memory_access) | variable

    # expressions

    rule :additive, ((r(:multiplicative)[:left] > ws > one_of('+', '-')[:op] >
     ws > r(:additive)[:right]) >> ->(s) {
      [s[:op].text, s[:left], s[:right]]
    }) | r(:multiplicative)

    rule :multiplicative, ((r(:primary)[:left] > ws > one_of('*', '/', '%', '^')[:op] >
     ws > r(:multiplicative)[:right]) >> ->(s) {
      [s[:op].text, s[:left], s[:right]]
    }) | r(:primary)

    rule :primary, ((one_of('(') > ws > r(:additive)[:group] > ws > one_of(')')) >> ->(s) {
      s[:group]
    }) | basic

    rule :arithmetic, r(:additive)

    # comparison expressions

    comparisons = (r(:arithmetic)[:left] > ws > (one_of('<', '>') | m('==') | m('!=') | m('<=') | m('>='))[:op] >
     ws > r(:arithmetic)[:right]) >> ->(s) {
      [s[:op].text, s[:left], s[:right]]
    }

    # memory access

    rule :memory_access, (m('M[') > cut! > ws > r(:arithmetic)[:expression] > ws > one_of(']')) >> ->(s) {
      ['memory access', s[:expression]]
    }

    # assignment

    lvalue = r(:memory_access) | variable

    assignment = (lvalue[:left] > ws > one_of('=') > cut! > ws > r(:arithmetic)[:right]) >> ->(s) {
      ['=', s[:left], s[:right]]
    }

    rule :start, assignment | comparisons | r(:arithmetic)
  end

  def self.parse(str); @grammar.parse(str); end

end
