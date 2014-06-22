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
      exprs = expressions.map {|e| e.compile(compile_data)}
      comparisons = exprs[0...-1].zip(exprs[1..-1]).map {|a, b| a + b + I[comparison]}.flatten
      comparisons + I[:&] * (expressions.length - 2)
    end

  end

  ##
  # Keeps track of some global counters and data as we compile C-variant code into
  # VM code.

  class CompileData
    attr_reader :structs

    def initialize; @label_counter, @structs = -1, {}; end

    def get_label; "label#{@label_counter += 1}".to_sym; end

  end

  # AST classes

  class Identifier < Struct.new(:value); end

  class ConstExp < Struct.new(:value)

    ##
    # Just load the constant.
    # :loadc self.value

    def compile(_); I[:loadc, value]; end

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

    def compile(compile_data); expression.compile(compile_data) + I[:!]; end

  end

  class NegExp < Struct.new(:expression)

    ##
    # e :-@

    def compile(compile_data); expression.compile(compile_data) + I[:-@]; end

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
      test.compile(compile_data) + I[:jumpz, else_target] +
       true_branch.compile(compile_data) + I[:jump, end_target] + I[:label, else_target] +
       false_branch.compile(compile_data) + I[:label, end_target]
    end

  end

  class While < Struct.new(:test, :body)

    ##
    # [:test] test jumpz(:end) body jump(:test) [:end]
    # Pretty similar to how we compile "if" statements. We have some jump targets and a test
    # to figure out where to jump.

    def compile(compile_data)
      test_target, end_target = compile_data.get_label, compile_data.get_label
      I[:label, test_target] + test.compile(compile_data) + I[:jumpz, end_target] +
       body.compile(compile_data) + I[:jump, test_target]
    end

  end

  class For < Struct.new(:init, :test, :update, :body)

    ##
    # For loop for(e1;e2;e3;) { s } is equivalent to e1; while (e2) { s; e3; } so we compile it as
    # init [:test] test jumpz(:end) body update jump(:test) [:end]
    # A bit convoluted but manageable.

    def compile(compile_data)
      test_target, end_target = compile_data.get_label, compile_data.get_label
      init.compile(compile_data) + I[:label, test_target] +
       test.expression.compile(compile_data) + I[:jumpz, end_target] +
       body.compile(compile_data) + update.compile(compile_data) + I[:pop, 1] +
       I[:jump, test_target] + I[:label, end_target]
    end

  end

  class CaseFragment < Struct.new(:case, :body)

    ##
    # Just compile the body. The rest is taken care of by the parent node
    # which should always be a +Switch+ node.

    def compile(compile_data); body.compile(compile_data); end

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
        cases.map do |c|
          I[:dup] + I[:loadc, (c_val = c.case.value)] + I[:==] + I[:jumpnz, labels[c_val]]
        end.flatten
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
    # generate the binary search ladder for the cases and place it before the case blocks.

    def compile(compile_data)
      # Sort and generate labels for the cases.
      default_label = compile_data.get_label
      sorted_cases = cases.sort {|a, b| a.case.value <=> b.case.value}
      labels = sorted_cases.reduce({}) {|m, c| m[c.case.value] = compile_data.get_label; m}
      # Generate the binary search ladder.
      binary_search_sequence = generate_binary_search_code(sorted_cases, labels, compile_data)
      # Compile the test expression, attach the binary search ladder and the code for each case.
      (test.compile(compile_data) + binary_search_sequence + I[:jump, default_label] +
       sorted_cases.map {|c| I[:label, labels[c.case.value]] + c.compile(compile_data)} +
       I[:label, default_label] + default.compile(compile_data)).flatten
    end

  end

  class Statements < Struct.new(:statements)

    ##
    # s1 pop s2 pop s3 pop ... sn pop

    def compile(compile_data); statements.map {|s| s.compile(compile_data)}.flatten; end

  end

  class ExpressionStatement < Struct.new(:expression)

    ##
    # Pretty simple. Compile the expression and then pop.

    def compile(compile_data); expression.compile(compile_data) + I[:pop, 1]; end

  end

  # Base types.
  class BaseType
    def self.size(_); 1; end
  end

  class IntType < BaseType; end

  class FloatType < BaseType; end

  class BoolType < BaseType; end

  class VoidType < BaseType
    def size(_); 0; end
  end

  # Semi-base types.
  class ArrayType < Struct.new(:type, :count)

    ##
    # Size of an array is exactly what you'd expect it to be.

    def size(_); count * type.size(_); end

  end

  class PtrType < Struct.new(:type)

    ##
    # Pointers are just integers and in our VM scheme they take up just 1 memory cell.

    def size(_); 1; end

  end

  # Derived types.
  class DerivedType < Struct.new(:name)

    ##
    # To figure out the size of a derived type we first have to look it up in the compilation
    # context and return the size of whatever struct was declared by that name.

    def size(compile_data); compile_data.structs[name].size(compile_data); end

  end

  class StructMember < Struct.new(:type, :name)

    ##
    # Size of a struct member is the size of the underlying type.

    def size(compile_data); @size ||= type.size(compile_data); end

  end

  class StructDeclaration < Struct.new(:name, :members)

    ##
    # The offset for the struct members is exactly what you'd expect. It is the sum of all
    # the members that are declared before that member and this information is computed when
    # we compute the total size of the struct because that information is available during the
    # total size calculation.
    
    def offset(compile_data, member)
      # Call size to instantiate +@offsets+ hash and then lookup the member in the hash.
      size(compile_data)
      if (member_offset = @offsets[member]).nil?
        raise StandardError, "Unknown struct member #{member} for struct #{name}."
      end
      member_offset
    end

    ##
    # The size of a declared struct is the sum of the sizes of all its members and as
    # we are computing the size of the entire struct we can also compute and save the offsets
    # for the struct members in +@offsets+.

    def size(compile_data)
      @offsets ||= {}
      @size ||= members.reduce(0) do |m, member|
        @offsets[member.name] = m
        m + member.size(compile_data)
      end
    end

    ##
    # Compiling struct declarations means putting information in a symbol table for the given struct.

    def compile(compile_data)
      if !compile_data.structs[name].nil?
        raise StandardError, "A struct by the given name is already defined: #{name}."
      end
      compile_data.structs[name] = self
    end

  end

  class VariableDeclaration < Struct.new(:type, :variable, :value); end

  class FunctionDefinition < Struct.new(:return_type, :name, :arguments, :body); end

  class ArgumentDefinition < Struct.new(:type, :name); end

  class ReturnStatement < Struct.new(:return); end

  class FunctionCall < Struct.new(:name, :arguments); end

end
