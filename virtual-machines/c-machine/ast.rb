require './cmachine'
I = CMachine::Instruction

module CMachineGrammar

  ##
  # Arithmetic and order operations have a common structure when it comes to compiling them
  # to stack operations so factor out that functionality.

  class OpReducers < Struct.new(:expressions)

    ##
    # e.g. :+, :-, :/, :*

    def reduce_with_operation(compile_data, operation)
      self.expressions.map {|e| e.compile(compile_data)}.reduce(&:+) + I[operation] * (self.expressions.length - 1)
    end

    ##
    # e.g. :<, :==, :>, etc.

    def reduce_with_comparison(compile_data, comparison)
      exprs = self.expressions.map {|e| e.compile(compile_data)}
      comparisons = exprs[0...-1].zip(exprs[1..-1]).map {|a, b| a + b + I[comparison]}.reduce(&:+)
      comparisons + I[:&] * (self.expressions.length - 2)
    end

  end

  class CompileData < Struct.new(:labels, :variables, :types); end

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
       self.test.compile(compile_data) + I[:jumpz, end_target] +
       self.body.compile(compile_data) + I[:jump, test_target] + I[:label, end_target]
    end

  end

  class CaseFragment < Struct.new(:case, :body); end

  class Switch < Struct.new(:test, :cases, :default); end

  class StatementBlock < Struct.new(:statements); end

  class Statements < Struct.new(:statements)

    ##
    # s1 pop s2 pop s3 pop ... sn pop

    def compile(compile_data); self.statements.map {|s| s.compile(compile_data) + I[:pop, 1]}.reduce(&:+); end

  end

  class IntType; end

  class FloatType; end

  class BoolType; end

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
