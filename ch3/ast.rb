module LetGrammar

  class ConstExpr < Struct.new(:value); end
  class VarExpr < Struct.new(:value); end
  class DiffExpr < Struct.new(:first, :second); end
  class ZeroExpr < Struct.new(:value); end
  class IfExpr < Struct.new(:test, :then, :else); end
  class LetExpr < Struct.new(:var, :value, :body); end

end
