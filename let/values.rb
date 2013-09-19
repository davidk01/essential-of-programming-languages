module LetGrammar

  class NumVal < Struct.new(:value); end
  class BoolVal < Struct.new(:value); end
  class ListVal < Struct.new(:value); end
  class ProcVal < Struct.new(:value, :env); end

end
