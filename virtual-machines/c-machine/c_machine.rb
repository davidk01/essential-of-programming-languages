require 'pegrb'

# The grammar that describes the subset of C we are going to work with.
# I have taken some liberties with how arithmetic operations are defined
# because I don't want to worry about precedence. So all arithmetic operations
# are written prefix style, e.g. {+, -, *}(x, y, z, -(1, 2, 3)).
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
  class GreaterExp < Struct.new(:expresssions); end
  class GreaterEqExp < Struct.new(:expressions); end
  class NotExp < Struct.new(:expression); end
  class NegExp < Struct.new(:expression); end

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

    identifier = one_of(/[^\s\(\)\,]/).many[:chars] >> ->(s) {
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

    rule :expression, arithmetic_expression | unary_expression | number | identifier

    rule :start, r(:expression)

  end

  def self.parse(iterable); @grammar.parse(iterable); end

end

# The actual VM class.
class CMachine

  # An instruction is just a symbol along with any necessary arguments.
  # E.g. +Instruction.new(:loadc, [1])+
  class Instruction < Struct.new(:instruction, :arguments); end

  # We need to keep track of the top of the stack (not sure why?) so
  # encapsulate that logic in one place to make sure the invariant is enforced.
  class Stack < Struct.new(:store, :sp)
    def initialize; super([], -1); end
    def pop; self.sp = self.sp - 1; self.store.pop; end
    def push(*args); self.sp = self.sp + args.length; self.store.push(*args); end
    def [](val); self.store[val]; end
    def []=(address, val); self.store[address] = val; end
    def top_value; self.store[-1]; end
  end

  # Set up the initial stack and registers.
  def initialize(c)
    @code, @stack = c, Stack.new
    @pc, @ir = -1, nil
  end

  # Retrieve next instruction and execute it.
  def step
    @ir = @code[@pc += 1]
    execute
  end

  # Instruction dispatcher.
  def execute
    case (sym = @ir.instruction)
    when :pop
      @ir.arguments[0].times { @stack.pop }
    when :loadc
      @stack.push(@ir.arguments[0])
    when :load
      starting, count = @stack.pop, @ir.arguments[0]
      (0...count).each do |i|
        @stack.push @stack[starting + i]
      end
    when :store
      ending = @stack.pop + (count = @ir.arguments[0]) - 1
      address = @stack.sp
      (0...count).each do |i|
        @stack[ending - i] = @stack[address - i]
      end
    when :loada
      starting, count = *@ir.arguments
      (0...count).each do |i|
        @stack.push @stack[starting + i]
      end
    when :storea
      ending = @ir.arguments[0] + (count = @ir.arguments[1]) - 1
      address = @stack.sp
      (0...count).each do |i|
        @stack[ending - i] = @stack[address - i]
      end
    when :jump
      @pc = @ir.arguments[0]
    when :jumpz
      condition = @stack.pop
      if condition == 0 then @pc = @ir.arguments[0] end
    when :jumpi
      add = @stack.pop
      @pc = @ir.arguments[0] + add
    when :dup
      @stack.push @stack.top_value
    when :*, :/, :+, :-, :%
      right = @stack.pop
      left = @stack.pop
      @stack.push left.send(sym, right)
    when :==, :!=, :<, :<=, :>, :>=
      right = @stack.pop
      left = @stack.pop
      @stack.push(left.send(sym, right) ? right : 0)
    when :-@
      @stack.push @stack.pop.send(sym)
    when :!
      @stack.push((el = @stack.pop) != 0 ? 0 : 1)
    end
  end

  def run
    raise StandardError
  end

end
