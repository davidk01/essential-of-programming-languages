require './cmachine'
I = CMachine::Instruction

module CMachineGrammar

  class CompileData < Struct.new(:labels, :variables, :types); end

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

  class GreaterExp < Struct.new(:expressions); end

  class GreaterEqExp < Struct.new(:expressions); end

  class NotExp < Struct.new(:expression); end

  class NegExp < Struct.new(:expression); end

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

  class Statements < Struct.new(:statements); end

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
