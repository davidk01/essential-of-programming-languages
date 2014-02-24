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
  class GreaterExp < Struct.new(:expressions); end
  class GreaterEqExp < Struct.new(:expressions); end
  class NotExp < Struct.new(:expression); end
  class NegExp < Struct.new(:expression); end
  class Assignment < Struct.new(:left, :right); end
  class If < Struct.new(:test, :true_branch, :false_branch); end
  class While < Struct.new(:test, :body); end
  class For < Struct.new(:init, :test, :update, :body); end
  class CaseFragment < Struct.new(:case, :body); end
  class Switch < Struct.new(:test, :cases, :default); end
  class StatementBlock < Struct.new(:statements); end
  class Statements < Struct.new(:statements); end
  class IntType; end
  class FloatType; end
  class BoolType; end
  class DerivedType < Struct.new(:type); end
  class PtrType < Struct.new(:type); end
  class ArrayType < Struct.new(:type, :count); end
  class VariableDeclaration < Struct.new(:type, :variable, :value); end
  class FunctionDefinition < Struct.new(:return_type, :arguments, :body); end
  class ArgumentDefinition < Struct.new(:type, :name); end
  class ReturnStatement < Struct.new(:return); end

end
