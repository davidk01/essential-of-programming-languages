class TypingContext

  def initialize(parent = {})
    @context, @parent, @current_function = {}, parent, nil
  end

  def []=(key, value)
    @context[key] = value
  end

  def increment
    self.class.new(self)
  end

  def [](key)
    @context[key] || @parent[key]
  end

  ##
  # When we are type checking a function declaration we need to set the current function so that
  # we can verify all return statements conform to the return type of the function.

  def current_function=(func)
    @current_function = func
  end

  def current_function
    @current_function || @parent.current_function
  end

end
