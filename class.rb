# -*- coding: utf-8 -*-

$debug = 1;

# Define exceptions that will be used to signal errors

class VarNotFound < StandardError
end

class ObjAlreadyDefined < StandardError
end

class Scope
  # Ugly solution, might be able to fix it later
  attr_accessor :scope_var, :scope_func, :parent
  
  def initialize(parent = nil)
    @scope_var, @scope_func = {}, {}, parent
  end

  def add_var(var)
    if $debug then
      temp = self
      while not temp.nil? and not temp.scope_var.has_key? var.name do
        temp = temp.parent
      end
      if temp != nil and temp != self then
        puts "Shadowing variable #{var.name} from previous scope"
      end
    end
    @scope_var[var.name] = var.value
  end

  def get_var(name)
    temp = self
    # dynamic scope, iterate backwards through scopes until we find the variable
    while not temp.nil? and not temp.scope_var.has_key? name do
      temp = temp.parent
    end

    # if we have the key, we return it.
    # if we don't, we know we've iterated to nil and we can raise an exception
    if temp.scope_var.has_key? name then
      return temp.scope_var[name]
    end

    raise VarNotFound, "In Scope: Unable to find variable with name #{name}"
  end

  def update_var(name, value)
    temp = self
    while not temp.parent.nil? and not temp.scope_var.has_key? name do
      temp = temp.parent
    end
    if $debug and temp != self then
      puts "Updated variable in older scope"
    end
    temp.scope_var[name] = value
  end

  def add_func(func)
    if $debug then
      temp = self
      while not temp.nil? and not temp.scope_func.has_key? func.name do
        temp = temp.parent
      end
      if temp != self then
        puts "Shadowing function #{func.name} from previous scope"
      end
    end
    @scope_func[func.name] = [func.type, func.body]
  end

  def get_func(name)
    temp = self
    # dynamic scope, iterate backwards through scopes until we find the variable
    while not temp.nil? and not temp.scope_func.has_key? name do
      temp = temp.parent
    end

    # if we have the key, we return it.
    # if we don't, we know we've iterated to nil and we can cast an exception
    if temp.scope_func.has_key? name then
      return temp.scope_func[name]
    end

    raise VarNotFound, "In Scope: Unable to find function with name #{name}"
  end
end

# A helper function that takes a scope and a variable as a argument.
# Will return a value based on the type of object, or nil if there is no value.
def get_var(scope, var)
  if var.is_a? IdentifierNode then
    return scope.get_var(var.name)
  elsif (var.is_a? IntegerNode) or (var.is_a? FloatNode) then
    return var.eval(scope)
  end
  
  return nil
end

# ProgramRoot will act as the root node of the program tree
class ProgramRoot
  def initialize(stmt_list)
    @stmt_list = stmt_list
    @scope = Scope.new
  end

  def eval
    @stmt_list.each do |stmt|
      stmt.eval(@scope)
    end
  end
end

# Implementation of common functions

# A basic node handling output
class PrintNode
  def initialize(input)
    @input = input
  end

  def eval(scope)
    @input.each do |stmt|
      val = get_var(scope, stmt);
      puts(val.eval(scope)) if val
    end
  end
end

# A basic node allowing input to be retrieved
class InputNode
  def initialize(input)
    @input = input
  end

  def eval(scope)
    @input.each do |stmt|
      puts "-----INPUT-----" if $debug
      user_input = gets
      scope.update_var(stmt, user_input)
    end
  end
end

class InsertNode
  def initialize(id, expr)
    @id = id
    @expr = expr
  end

  def eval(scope)
    new_list = get_var(scope, @id)
    if new_list.is_a? ListNode then
      new_list << expr.eval(scope)
    else
      raise TypeError, "Expected ListNode, got #{new_list.class}"
    end
  end
end

# A node handling removal of items from the built-in list
# A index of -1 will remove the last item
class RemoveNode
  def initialize(id, index)
    @id, @index = id, index
  end

  def eval(scope)
    new_list = get_var(scope, @id)
    # array indexes can have a -(minus) prepended which will cause Ruby
    # to select the element from the right side
    raise(IndexError, "Index out of bounds") if @index.abs > (new_list.size - 1)
    new_list.delete_at @index
    scope.update_var(@id, new_list)
  end
end

class InsertNode
  def initialize(id, expr, index = nil)
    @id, @expr, @index = id, expr, index
  end

  def eval(scope)
    new_list = get_var(scope, @id)
    # new_list might be nil
    # new_list.size could be the new last index, so (size + 1) would be too much
    if (not new_list.nil?) and (@index.abs > (new_list.size + 1)) then
      raise(IndexError, "Index out of bounds")
    end

    if new_list.nil? then
      new_list << @expr.eval(scope)
    else
      new_list.insert(@index, @expr.eval(scope))
    end

    scope.update_var(@id, new_list)
  end
end

class AtNode
  def initialize(id, index)
    @id, @index = id, index
  end

  def eval(scope)
    new_list = get_var(scope, @id)
    raise IndexError, "Index out of bounds" if @index.abs > new_list.size
    return new_list[@index]
  end
end

class LengthNode
  def initialize(id)
    @id = id
  end

  def eval(scope)
    get_var(scope, @id).size
  end
end

class IfStmtNode
  def initialize(cond, stmts)
    @cond, @stmts = cond, stmts
  end

  def eval(scope)
    @child_scope = Scope(scope)
    if @cond.eval then
      @stmts.each do |stmt|
        stmt.eval(@child_scope)
      end
    end
  end
end

class IfElseStmtNode
  def initialize(cond, stmts)
    @cond, @stmts = cond, stmts
  end

  def eval(scope)
    @child_scope = Scope(scope)
    if @cond.eval then
      @stmts.each do |stmt|
        stmt.eval(@child_scope)
      end
    end
  end
end

class ElseStmtNode
  def initialize(stmts)
    @stmts = stmts
  end

  def eval(scope)
    @child_scope = Scope(scope)
    @stmts.each do |stmt|
      stmt.eval(@child_scope)
    end
  end
end

class ForStmtNode
  def initialize(assign_stmt, test_stmt, incr_expr, stmts)
    @assign_stmt, @test_stmt = assign_stmt, test_stmt
    @incr_expr, @stmts = incr_expr, stmts
  end

  def eval(scope)
    # We want the execution to take place in its own scope
    @new_scope = Scope(scope)
    @assign_stmt.eval(@new_scope)
    while @test_stmt.eval(@new_scope) do
      @stmts.each do |stmt|
        stmt.eval(@new_scope)
      end
      # eval @incr_expr after each loop as to (hopefully) avoid an infinite loop
      @incr_expr.eval(@new_scope)
    end
  end
end

class WhileStmtNode
  def initialize(expr, stmts)
    @expr, @stmts = expr, stmts
  end

  def eval(scope)
    @new_scope = Scope(scope)
    while @expr.eval(@new_scope) do
      @stmts.each do |stmt|
        stmt.eval(@new_scope)
      end
    end
  end
end

# TODO: Create this function.
#       Maybe it can be empty, and we instead check if we find a ReturnNode
#       where appropriate(in WhileStmtNode etc.)
class ReturnNode
  def initialize(expr)
    @expr = expr
  end
  
  def eval(scope)
    #getCurrScopeFunc.return?
  end
end

# Data types

# A simple, constant node
class ValueNode
  def initialize(val = nil)
    raise ArgumentError, "Can't make a constant variable without val" if not val
    @val = val
  end

  def eval(scope)
    @val
  end  
end

# TODO: to_string in every class, so that print works
class IntegerNode < ValueNode
end

class FloatNode < ValueNode
end

class StringNode < ValueNode
end

class BoolNode < ValueNode
end

class ListNode < ValueNode
end

# TODO: Type should determine what type of object to create, and save the object
#       in its value.
class IdentifierNode
  attr_reader :name, :value

  def initialize(name, type, value = nil)
    # Encapsulates the value in the appropriate node
    case type
    when "int"
      value = IntegerNode.new(value)
    when "float"
      value = FloatNode.new(value)
    when "string"
      value = StringNode.new(value)
    when "bool"
      value = BoolNode.new(value)
    when "list"
      value = ListNode.new(value)
    end
    @name, @value = name, value
  end

  def eval(scope)
    scope.add_var(self)
  end

  def get_val(scope)
    @value.eval(scope)
  end
end

# Boolean statements and Numerical statements

# Nice solution to a later problem
oper_to_func = {"ge" => :>=, "gt" => :>, "le" => :<=,
  "lt" => :<, "eq" => :==}

# This function will, given a value, ``calculate'' whether it's true or false.
def val_to_bool(value, scope)
  case value.is_a?
  when IdentifierNode
    identifier = scope.get_var(value.name)
    # Next time value_to_boolean() evaluates it won't have a IdentifierNode
    return value_to_boolean(identifier.get_val(scope), scope)
  when IntegerNode
    return value.eval(scope) > 0
  when FloatNode
    # Doesn't make a lot of sense. Provided as a convenience.
    return value.eval(scope) > 0
  when StringNode
    # Convenience.
    return value.eval(scope).size > 0
  when BoolNode
    # SHOULD already be a boolean value
    return value.eval(scope)
  when ListNode
    return value.eval(scope).size > 0
  end
end

class AndNode
  def initialize(op1, op2)
    @op1, @op2 = op1, op2
  end

  def eval(scope)
    if @op1.is_a? 
    end
    val_to_bool(@op1, scope) and val_to_bool(@op2, scope)
  end
end

class OrNode
  def initialize(op1, op2)
    @op1, @op2 = op1, op2
  end

  def eval(scope)
    val_to_bool(@op1, scope) or val_to_bool(@op2, scope)
  end
end

class NotNode
  def initialize(op1)
    @op1 = op1
  end

  def eval(scope)
    not val_to_bool(@op1, scope)
  end
end

class ComparisonNode
  def initialize(op1, oper, op2)
    @op1, @oper, @op2 = op1, oper, op2
  end

  def eval(scope)
    # Works like this:
    # 1. get boolean value of @op1
    # 2. We then use send to send the following parameters:
    #     The first is a lookup of what operator to use
    #     Then we get the boolean value and send this to the operator
    # We are left with a boolean value which is returned
    val_to_bool(@op1, scope).send(oper_to_func(@oper), val_to_bool(@op2, scope))
  end
end

class BinaryOperatorNode
  def initialize(op1, oper, op2)
    @op1, @oper, @op2 = op1, oper, op2
  end

  def eval(scope)
    @op1.eval(scope).send(@oper, @op2.eval(scope))
  end
end

class AddNode < BinaryOperatorNode
  def initialize(op1, op2)
    super(op1, :+, op2)
  end
end

class SubtractNode < BinaryOperatorNode
  def initialize(op1, op2)
    super(op1, :-, op2)
  end
end

class MultiplyNode < BinaryOperatorNode
  def initialize(op1, op2)
    super(op1, :*, op2)
  end
end

class DivisionNode < BinaryOperatorNode
  def initialize(op1, op2)
    super(op1, :/, op2)
  end
end

class PowerNode < BinaryOperatorNode
  def initialize(op1, op2)
    super(op1, :**, op2)
  end
end

class UnaryOperatorNode
  def initialize(op1, oper)
    @op1, @oper = op1, oper
  end

  def eval(scope)
    @op1.send(@oper)
  end
end

class UnaryPlusNode < UnaryOperatorNode
  def initialize(op1)
    super(op1, :+@)
  end
end

class UnaryMinusNode < UnaryOperatorNode
def initialize(op1)
    super(op1, :-@)
  end
end

