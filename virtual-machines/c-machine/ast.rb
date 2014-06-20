require_relative './cmachine'
I = CMachine::Instruction

module CMachineGrammar

  ##
  # Arithmetic and order operations have a common structure when it comes to compiling them
  # to stack operations so factor out that functionality.

  class OpReducers < Struct.new(:expressions)

    ##
    # e.g. :+, :-, :/, :*

    def reduce_with_operation(compile_data, operation)
      expr = self.expressions.map {|e| e.compile(compile_data)}
      expr[0] + expr[1..-1].map {|e| e + I[operation]}.flatten
    end

    ##
    # e.g. :<, :==, :>, etc.

    def reduce_with_comparison(compile_data, comparison)
      exprs = self.expressions.map {|e| e.compile(compile_data)}
      comparisons = exprs[0...-1].zip(exprs[1..-1]).map {|a, b| a + b + I[comparison]}.flatten
      comparisons + I[:&] * (self.expressions.length - 2)
    end

  end

  class CompileData

    def initialize; @label_counter = -1; end

    def get_label; "label#{@label_counter += 1}".to_sym; end

  end

  # AST classes

  class Identifier < Struct.new(:value); end

  class ConstExp < Struct.new(:value)

    ##
    # Just load the constant.
    # :loadc self.value

    def compile(_); I[:loadc, self.value]; end

  end

  class DiffExp < OpReducers

    ##
    # For each expression in the list of expressions we compile it and then we append n - 1 :- operations,
    # where n is the length of the expressions. e1 e2 e3 ... en :- :- ... :-.

    def compile(compile_data); reduce_with_operation(compile_data, :-); end

  end

  class AddExp < OpReducers

    ##
    # Same reasoning as for +DiffExp+ except we use :+.

    def compile(compile_data); reduce_with_operation(compile_data, :+); end

  end

  class MultExp < OpReducers

    ##
    # Same as above.

    def compile(compile_data); reduce_with_operation(compile_data, :*); end

  end

  class DivExp < OpReducers

    # Same as above.

    def compile(compile_data); reduce_with_operation(compile_data, :/); end

  end

  class LessExp < OpReducers

    ##
    # e1 e2 :< e2 e3 :< e3 e4 :< ... en-1 en :< :& :& ... :&

    def compile(compile_data); reduce_with_comparison(compile_data, :<); end

  end

  class LessEqExp < OpReducers

    ##
    # Same as above.

    def compile(compile_data); reduce_with_comparison(compile_data, :<=); end

  end

  class EqExp < OpReducers

    ##
    # Same as above.

    def compile(compile_data); reduce_with_comparison(compile_data, :==); end

  end

  class GreaterExp < OpReducers

    ##
    # Same as above.

    def compile(compile_data); reduce_with_comparison(compile_data, :>); end

  end

  class GreaterEqExp < OpReducers

    ##
    # Same as above.

    def compile(compile_data); reduce_with_comparison(compile_data, :>=); end

  end

  class NotExp < Struct.new(:expression)

    ##
    # e :!

    def compile(compile_data); self.expression.compile(compile_data) + I[:!]; end

  end

  class NegExp < Struct.new(:expression)

    ##
    # e :-@

    def compile(compile_data); self.expression.compile(compile_data) + I[:-@]; end

  end

  class Assignment < Struct.new(:left, :right); end

  class If < Struct.new(:test, :true_branch, :false_branch)

    ##
    # test jumpz(:else) true_branch jump(:end) [:else] false_branch [:end]
    # Jump targets are in terms of symbolic labels which later become actual addresses
    # during a post-processing step. The labels themselves stay in the code but the VM
    # interprets them as no-ops.

    def compile(compile_data)
      else_target, end_target = compile_data.get_label, compile_data.get_label
      self.test.compile(compile_data) + I[:jumpz, else_target] +
       self.true_branch.compile(compile_data) + I[:jump, end_target] + I[:label, else_target] +
       self.false_branch.compile(compile_data) + I[:label, end_target]
    end

  end

  class While < Struct.new(:test, :body)

    ##
    # [:test] test jumpz(:end) body jump(:test) [:end]
    # Pretty similar to how we compile "if" statements. We have some jump targets and a test
    # to figure out where to jump.

    def compile(compile_data)
      test_target, end_target = compile_data.get_label, compile_data.get_label
      I[:label, test_target] + self.test.compile(compile_data) + I[:jumpz, end_target] +
       self.body.compile(compile_data) + I[:jump, test_target]
    end

  end

  class For < Struct.new(:init, :test, :update, :body)

    ##
    # For loop for(e1;e2;e3;) { s } is equivalent to e1; while (e2) { s; e3; } so we compile it as
    # init [:test] test jumpz(:end) body update jump(:test) [:end]
    # A bit twisty but manageable.

    def compile(compile_data)
      test_target, end_target = compile_data.get_label, compile_data.get_label
      self.init.compile(compile_data) + I[:label, test_target] +
       self.test.expression.compile(compile_data) + I[:jumpz, end_target] +
       self.body.compile(compile_data) + self.update.compile(compile_data) + I[:pop, 1] +
       I[:jump, test_target] + I[:label, end_target]
    end

  end

  class CaseFragment < Struct.new(:case, :body)

    ##
    # Just compile the body. The rest is taken care of by the parent node
    # which should always be a +Switch+ node.

    def compile(compile_data); self.body.compile(compile_data); end

  end

  class Switch < Struct.new(:test, :cases, :default)

    ##
    # Assume the cases are sorted then generating the code is pretty simple.
    # The base case is less than 3 case values. For less than 3 values we generate
    # a simple comparison ladder. For the non-base case we proceed recursively by
    # breaking things into middle, top, bottom and then concatenating the generated code
    # with appropriate jump targets when the case matches and jumps to the other pieces of
    # the ladder when it doesn't.

    def generate_binary_search_code(cases, labels, compile_data)
      if cases.length < 3
        cases.map {|c| I[:dup] + I[:loadc, (c_val = c.case.value)] + I[:==] + I[:jumpnz, labels[c_val]]}.flatten
      else
        # mid top :less bottom
        midpoint, less_label = cases.length / 2, compile_data.get_label
        middle, bottom, top = cases[midpoint], cases[0...midpoint], cases[(midpoint + 1)..-1]
        I[:dup] + I[:loadc, (m_val = middle.case.value)] + I[:==] + I[:jumpnz, labels[m_val]] +
         I[:dup] + I[:loadc, m_val] + I[:<] + I[:jumpnz, less_label] +
         generate_binary_search_code(top, labels, compile_data) + I[:label, less_label] +
         generate_binary_search_code(bottom, labels, compile_data)
      end
    end

    ##
    # We are going to use binary search to figure out which case statement to jump to.
    # First we sort the case statements and assign jump targets to each statement. Then we
    # generate the binary search for the cases and place it before the case blocks.
    # Test Data: "switch (1) {\n  case 1: { 1; }\n  case 2: { 2; }\n  case 3: { 3; }\n  case 4: { 4; }\n  case 5: { 5; }\n  case 6: { 6; }\n  case 7: { 7; }\n  default: { 111; }\n}\n"

    def compile(compile_data)
      default_label = compile_data.get_label
      sorted_cases = self.cases.sort {|a, b| a.case.value <=> b.case.value}
      labels = sorted_cases.reduce({}) {|m, c| m[c.case.value] = compile_data.get_label; m}
      binary_search_sequence = generate_binary_search_code(sorted_cases, labels, compile_data)
      (self.test.compile(compile_data) + binary_search_sequence + I[:jump, default_label] + sorted_cases.map {|c|
        I[:label, labels[c.case.value]] + c.compile(compile_data)
      } + I[:label, default_label] + self.default.compile(compile_data)).flatten
    end

  end

  class Statements < Struct.new(:statements)

    ##
    # s1 pop s2 pop s3 pop ... sn pop

    def compile(compile_data); self.statements.map {|s| s.compile(compile_data)}.flatten; end

  end

  class ExpressionStatement < Struct.new(:expression)

    ##
    # Pretty simple. Compile the expression and then pop.

    def compile(compile_data); self.expression.compile(compile_data) + I[:pop, 1]; end

  end

  class IntType; end

  class FloatType; end

  class BoolType; end

  class VoidType; end

  class StructMember < Struct.new(:type, :name); end

  class StructDeclaration < Struct.new(:name, :members); end

  class DerivedType < Struct.new(:type); end

  class PtrType < Struct.new(:type); end

  class ArrayType < Struct.new(:type, :count); end

  class VariableDeclaration < Struct.new(:type, :variable, :value); end

  class FunctionDefinition < Struct.new(:return_type, :name, :arguments, :body); end

  class ArgumentDefinition < Struct.new(:type, :name); end

  class ReturnStatement < Struct.new(:return); end

  class FunctionCall < Struct.new(:name, :arguments); end

end
