defmodule JSONPointerTest do
  use ExUnit.Case
  # doctest JSONPointer

    obj = %{
      "a" => 1,
      "b" => %{
        "c" => 2
      },
      "d" => %{
        "e": [ %{"a" => 3}, %{"b" => 4}, %{"c" => 5} ]
      }
    }

    # draft example
    example = %{
      "foo" => ["bar", "baz"],
      "" => 0,
      "a/b" => 1,
      "c%d" => 2,
      "e^f" => 3,
      "g|h" => 4,
      "i\\j" => 5,
      "k\"l" => 6,
      " " => 7,
      "m~n" => 8
    }

    test "parse" do
      assert JSONPointer.parse( "" ) == { :ok, [] }

      assert JSONPointer.parse( "invalid" ) == { :error, "invalid json pointer: invalid" }

      assert JSONPointer.parse( "/some/where/over" ) == { :ok, [ "some", "where", "over" ] }

      assert JSONPointer.parse("/hello~0bla/test~1bla") == { :ok, ["hello~bla","test/bla"] };
    end

    test "compile" do
      # assert JSONPointer.compile( ["hello~bla", "test/bla"] ) == { :ok, "/hello~0bla/test~1bla" }
    end


    test "get" do

      obj = %{
        "a" => 1,
        "b" => %{ "c" => 2 },
        "d" => %{ "e" => [ %{"a" => 3}, %{"b" => 4}, %{"c" => 5} ] }
      }

      assert JSONPointer.get( obj, "/a") == {:ok, 1}

      assert JSONPointer.get( obj, "/b/c") == {:ok, 2}

      assert JSONPointer.get( obj, "/d/e/0/a") == {:ok, 3}

      assert JSONPointer.get( obj, "/d/e/1/b") == {:ok, 4}

      assert JSONPointer.get( obj, "/d/e/2/c") == {:ok, 5}

      assert JSONPointer.get( obj, "/d/e/3") ==
        {:error, "index 3 out of bounds in [%{\"a\" => 3}, %{\"b\" => 4}, %{\"c\" => 5}]"}

      assert JSONPointer.get( %{}, "" ) == {:ok, %{}}

    end

    test "set" do
      obj = %{
        "a" => 1,
        "b" => %{ "c" => 2 },
        "d" => %{ "e" => [ %{"a" => 3}, %{"b" => 4}, %{"c" => 5} ] }
      }

      assert JSONPointer.set( %{"a"=>1}, "/a", 2)  == {:ok, %{"a"=>2}, 1 }


    end

  end