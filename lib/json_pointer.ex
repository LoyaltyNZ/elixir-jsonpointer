defmodule JSONPointer do

  @doc """
    Looks up a JSON pointer in an object

    ## Examples
      iex> JSONPointer.get( %{ "example" => %{ "bla" => "hello" } }, "/example/bla" )
      {:ok, "hello"}
  """
  def get(obj, pointer) do
    case walk_container( :get, obj, pointer, nil ) do
      {:ok,_,value} -> {:ok,value}
      {:error,msg,value} -> {:error,msg,value}
    end
  end

  def get!(obj,pointer) do
    case walk_container( :get, obj, pointer, nil ) do
      {:ok,_,value} -> value
      {:error,msg,value} -> raise ArgumentError, message: msg
    end
  end

  @doc """
    Tests if an object has a value for a JSON pointer
  """
  def has( object, pointer ) do
    case walk_container( :has, object, pointer, nil ) do
      {:ok,_obj,_existing} -> true
      {:error,_,_} -> false
    end
  end

  @doc """
  Removes an attribute of object referenced by pointer
  """
  def remove(object, pointer) do
    walk_container( :remove, object, pointer, nil )
  end

  @doc """
  Sets a new value on object at the location described by pointer

    ## Examples

      iex> JSONPointer.set( %{}, "/example/msg", "hello")
      {:ok, %{ "example" => %{ "msg" => "hello" }}, nil }
  """
  def set( object, pointer, value ) do
    walk_container( :set, object, pointer, value )
  end





  # set the list at index to val
  defp apply_into( list, index, val ) when is_list(list) do
    if index do
      # ensure the list has the capacity for this index
      val = list |> ensure_list_size(index+1) |> List.replace_at(index, val)
    end
    val
  end


  # set the key to val within a map
  defp apply_into( map, key, val ) when is_map(map) do
    if key do
      val = Map.put(map, key, val)
    end
    val
  end



  # when an empty pointer has been provided, simply return the incoming object
  # @spec walk_container(atom, map | list, String.t, any ) :: any
  defp walk_container(_operation, object, "", _value ) do
    {:ok, nil, object}
  end

  defp walk_container(_operation, object, "#", _value ) do
    {:ok, nil, object}
  end

  # begins the descent into a container using the specified pointer
  # @spec walk_container( atom, map | list, String.t, any ) :: any
  defp walk_container(operation, object, pointer, value ) do
    case JSONPointer.parse(pointer) do
      {:ok, tokens} ->
        [token|tokens] = tokens
        walk_container( operation, nil, object, token, tokens, value )
      {:error, reason, value} ->
        {:error,reason, value}
    end
  end

  # leaf operation: remove from map
  defp walk_container( operation, _parent, map, token, tokens, _value ) when operation == :remove and tokens == [] and is_map(map) do
      case Map.fetch( map, token ) do
        {:ok, existing} ->
          {:ok, Map.delete(map, token), existing}
        :error ->
          {:error, "json pointer key not found %{token}", map}
      end
  end

  # leaf operation: remove from list
  defp walk_container( operation, _parent, list, token, tokens, _value ) when operation == :remove and tokens == [] and is_list(list) do
    case Integer.parse(token) do
      {index,_rem} ->
        {:ok, apply_into(list, index, nil), Enum.at(list,index) }
      :error ->
        {:error, "invalid json pointer invalid index #{token}", list}
    end
  end

  # leaf operation: set token to value on a map
  defp walk_container( operation, _parent, map, token, tokens, value ) when operation == :set and tokens == [] and is_map(map) do
      case Integer.parse(token) do
        {index,_rem} ->
            # the token turned out to be an array index, so convert the value into a list
            {:ok, apply_into([],index,value), nil}
        :error ->
          case Map.fetch( map, token ) do
            {:ok, existing} ->
              {:ok, apply_into(map, token,value), existing}
            :error ->
              {:ok, apply_into(map, token,value), nil}
          end
      end
  end

  # leaf operation: set token(index) to value on a list
  defp walk_container( operation, _parent, list, token, tokens, value ) when operation == :set and tokens == [] and is_list(list) do
    case Integer.parse(token) do
      {index,_rem} ->
        {:ok, apply_into(list, index, value), Enum.at(list,index) }
      :error ->
        {:error, "invalid json pointer invalid index #{token}", list}
    end
  end

  # leaf operation: no value for list, so we determine the container depending on the token
  defp walk_container(operation, parent, list, token, tokens, value ) when operation == :set and tokens == [] and is_list(parent) and list == nil do
    case Integer.parse(token) do
      {index,_rem} ->
        {:ok, apply_into([], index, value), nil }
      :error ->
        {:ok, apply_into(%{}, token, value), nil }
    end
  end

  # leaf operation: does map have token?
  defp walk_container(operation, _parent, map, token, tokens, _value) when (operation == :has or operation == :get) and tokens == [] and is_map(map) do
    if token == "**" do
      {:ok, nil, map}
    else
      case Map.fetch(map, token) do
        {:ok,existing} ->
          {:ok, nil, existing}
        :error ->
          {:error,"token not found #{token}", map}
      end
    end

  end

  # leaf operation: does list have index?
  defp walk_container(operation, _parent, list, token, tokens, _value) when (operation == :has or operation == :get) and tokens == [] and is_list(list) do
    if token == "**" do
      {:ok, nil,list}
    else
      case Integer.parse(token) do
        {index, _rem} ->
          if (index < Enum.count(list) && Enum.at(list,index) != nil) do
            {:ok,nil, Enum.at(list,index)}
          else
            {:error,"index #{index} out of bounds", list}
          end
        :error ->
          {:error,"token not found #{token}", list}
      end
    end
  end



  #
  defp walk_container( operation, _parent, map, "**", tokens, value ) when is_map(map) do
    [next_token|next_tokens] = tokens
    case Map.fetch(map, next_token) do
      {:ok, existing} ->
        walk_container( operation, map, map, next_token, next_tokens, value)
      :error ->
        map_res = Enum.reduce( Dict.keys(map), [], fn(map_key, acc) ->
          case walk_container( operation, map, Map.fetch!(map, map_key), "**", tokens, value) do
              {:ok, _, walk_res} ->
                case walk_res do
                    r when is_list( walk_res ) -> acc ++ walk_res
                    r -> acc ++ [walk_res]
                end
              {:error, msg, _value} -> acc
          end
          end)
        if List.first(map_res) == nil do
          {:error, "token not found: #{next_token}", map_res}
        else
          {:ok, nil, map_res }
        end
    end
  end

  defp walk_container( operation, _parent, list, "**", tokens, value ) when is_list(list) do
    [next_token|_] = tokens

    list_res = Enum.reduce(list, [], fn(entry, acc) ->
      case walk_container( operation, list, entry, "**", tokens, value) do
        {:ok, _, walk_val} ->
          acc ++ [ walk_val ]
        {:error, msg, _value} -> acc
      end
      end)

    list_res = {:ok, nil, list_res}
  end

  defp walk_container( operation, _parent, map, "**", tokens, value ) do
    [next_token|_] = tokens
    {:error,"token not found #{next_token}", map}
  end

  # recursively walk through a map container
  defp walk_container( operation, _parent, map, token, tokens, value ) when is_map(map) do
    [sub_token|tokens] = tokens

    case Map.fetch(map, token) do
      {:ok, existing} ->
        {res,sub,rem} = walk_container( operation, map, existing, sub_token, tokens, value)
        # re-apply the altered tree back into our map
        if res == :ok do
          {res,apply_into(map, token, sub),rem}
        else
          {res,sub,rem}
        end
      :error ->
        case operation do
          :set ->
            {res,sub,rem} = walk_container( operation, map, %{}, sub_token, tokens, value)
            {res,apply_into(map, token, sub),rem}
          :has ->
            {_res,_sub,_rem} = walk_container( operation, map, %{}, sub_token, tokens, value)
          _ ->
            {:error, "json pointer key not found #{token} on #{inspect map}",map}
        end
    end
  end

  # recursively walk through a list container
  defp walk_container( operation, _parent, list, token, tokens, value ) when is_list(list) do
    [sub_token|tokens] = tokens
    case Integer.parse(token) do
      {index,_rem} ->
        if (operation == :get or operation == :has) and index >= Enum.count(list) do
          {:error, "index #{index} out of bounds", list}
        else
          {res,sub,rem} = walk_container( operation, list, Enum.at(list,index), sub_token, tokens, value)
          # re-apply the returned result back into the current list
          {res, apply_into(list,index,sub), rem}
        end
      _ ->
        {:error, "token not found on list #{token}", list}
    end
  end

  # when there is no container defined, use the type of token to decide one
  defp walk_container( operation, _parent, container, token, tokens, value ) when operation == :set and container == nil do
    [sub_token|tokens] = tokens
    case Integer.parse(token) do
      {index,_rem} ->
        {res,sub,rem} = walk_container( operation, [], [], sub_token, tokens, value)
        # re-apply the returned result back into the current list
        {res, apply_into([],index,sub), rem}
      _ ->
        {res,sub,rem} = walk_container( operation, %{}, %{}, sub_token, tokens, value)
        # re-apply the returned result back into the current list
        {res, apply_into(%{},token,sub), rem}
    end
  end



  @doc """
    Escapes a reference token

    ## Examples

      iex> JSONPointer.escape "hello~bla"
      "hello~0bla"
      iex> JSONPointer.escape "hello/bla"
      "hello~1bla"

  """
  @spec escape(String.t) :: String.t
  def escape( str ) do
    str
    |> String.replace( "~", "~0" )
    |> String.replace( "/", "~1" )
    |> String.replace( "**", "~2" )
  end

  @doc """
  Unescapes a reference token

    ## Examples

      iex> JSONPointer.unescape "hello~0bla"
      "hello~bla"
      iex> JSONPointer.unescape "hello~1bla"
      "hello/bla"
  """
  @spec unescape(String.t) :: String.t
  def unescape( str ) do
    str
    |> String.replace( "~0", "~" )
    |> String.replace( "~1", "/" )
    |> String.replace( "~2", "**" )
  end


  @doc """
  Converts a JSON pointer into a list of reference tokens
  """

  def parse(""), do: {:ok,[]}

  def parse( pointer ) do

    # handle a URI Fragment
    if String.first(pointer) == "#", do: pointer = pointer |> String.lstrip(?#)

    case String.first(pointer) do

      "/" ->
        {:ok,
          pointer
          |> String.lstrip(?/)
          |> String.split("/")
          |> Enum.map( &URI.decode/1 )
          |> Enum.map( &JSONPointer.unescape/1) }


      _ ->
        {:error, "invalid json pointer", pointer}
    end


  end


  @doc """
  Ensures that the given list has size number of elements
  """
  def ensure_list_size(list, size) do
    diff = size - Enum.count(list)
    if diff > 0 do
      list = list ++ List.duplicate( nil, diff )
    end
    list
  end

end
