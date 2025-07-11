class UnaryOperators < Phlex::HTML
  def view_template
    # Test ! operator with method call
    if !condition?
      div { "negated" }
    end

    # Test ! operator with instance variable
    if !@instance_var
      span { "not set" }
    end

    # Test ! operator with parentheses
    if !(foo || bar)
      p { "neither" }
    end

    # Test 'not' operator
    if not active?
      div(class: "inactive") { "Inactive" }
    end

    # Test unary minus
    value = -count
    div { value }

    # Test unary plus
    positive = +number
    div { positive }

    # Test bitwise NOT
    mask = ~bits
    div { mask }
  end

  private

  def not_condition?
    !condition?
  end

  def condition?
    false
  end

  def foo
    nil
  end

  def bar
    nil
  end

  def active?
    false
  end

  def count
    42
  end

  def number
    -5
  end

  def bits
    0b1010
  end
end
