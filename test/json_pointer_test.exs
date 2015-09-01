defmodule JSONPointerTest do
  use ExUnit.Case
  doctest JSONPointer

  def dataBookStore do
    %{
      "store" => %{
        "book" => [
          %{
            "category" => "reference",
            "author" => "Nigel Rees",
            "title" => "Sayings of the Century",
            "price" => 8.95
          },
          %{
            "category" => "fiction",
            "author" => "Evelyn Waugh",
            "title" => "Sword of Honour",
            "price" => 12.99
          },
          %{
            "category" => "fiction",
            "author" => "Herman Melville",
            "title" => "Moby Dick",
            "isbn" => "0-553-21311-3",
            "price" => 8.99
          },
          %{
            "category" => "fiction",
            "author" => "J. R. R. Tolkien",
            "title" => "The Lord of the Rings",
            "isbn" => "0-395-19395-8",
            "price" => 22.99
          }
        ],
        "bicycle" => %{
          "color" => "red",
          "price" => 19.95
        }
    }}
  end

    test "get" do

      obj = %{
        "a" => 1,
        "b" => %{ "c" => 2 },
        "d" => %{ "e" => [ %{"a" => 3}, %{"b" => 4}, %{"c" => 5} ] }
      }

      assert JSONPointer.get(obj, "/a") == {:ok, 1}
      assert JSONPointer.get(obj, "/b/c") == {:ok, 2}

      assert JSONPointer.get(obj, "/d/e/0/a") == {:ok, 3}
      assert JSONPointer.get(obj, "/d/e/1/b") == {:ok, 4}
      assert JSONPointer.get(obj, "/d/e/2/c") == {:ok, 5}

      assert JSONPointer.get([],"/2") == {:error,"index 2 out of bounds", []}
      assert JSONPointer.get([],"/2/3") == {:error,"index 2 out of bounds", []}
      assert JSONPointer.get(obj, "/d/e/3") ==
        {:error, "index 3 out of bounds", obj["d"]["e"] }

      assert JSONPointer.get(%{}, "") == {:ok, %{}}

      assert JSONPointer.get(%{"200"=>%{"a" => "b"}},"/200") == {:ok, %{"a" => "b"}}
    end

    test "get URI fragment" do
      obj = %{
        "foo" => ["bar", "baz"],
        "" => 0,
        "a/b" => 1,
        "c%d" => 2,
        "e^f" => 3,
        "g|h" => 4,
        "i\\j" => 5,
        "k\"l" => 6,
        " " => 7,
        "m~n" => 8 }

      assert JSONPointer.get(obj, "#") == {:ok,obj}
      assert JSONPointer.get(obj, "#/foo") == {:ok, ["bar", "baz"]}
      assert JSONPointer.get(obj, "#/foo/0") == {:ok, "bar"}
      assert JSONPointer.get(obj, "#/") == {:ok, 0}
      assert JSONPointer.get(obj, "#/a~1b") == {:ok, 1}
      assert JSONPointer.get(obj, "#/c%25d") == {:ok, 2}
      assert JSONPointer.get(obj, "#/e%5Ef") == {:ok, 3}
      assert JSONPointer.get(obj, "#/g%7Ch") == {:ok, 4}
      assert JSONPointer.get(obj, "#/i%5Cj") == {:ok, 5}
      assert JSONPointer.get(obj, "#/k%22l") == {:ok, 6}
      assert JSONPointer.get(obj, "#/%20") == {:ok, 7}
      assert JSONPointer.get(obj, "#/m~0n") == {:ok, 8}

    end

    test "get using wildcard" do
      data = dataBookStore()
      assert JSONPointer.get( data, "/store/bicycle/color") == {:ok, "red"}
      assert JSONPointer.get(data, "/store/book/**/price") == {:ok, [8.95, 12.99, 8.99, 22.99]} # "the prices of all books in the store"
      assert JSONPointer.get(data, "/**/author") == {:ok, ["Nigel Rees", "Evelyn Waugh", "Herman Melville", "J. R. R. Tolkien"]} # "all authors"
      assert JSONPointer.get(data, "/store/**/price") == {:ok, [19.95, 8.95, 12.99, 8.99, 22.99]} # the price of everything in the store.

      assert JSONPointer.get(data, "/store/bicycle/**") == {:ok, %{"color" => "red", "price" => 19.95} }
      assert JSONPointer.get(data, "/store/**") == {:ok, data["store"] }
      assert JSONPointer.get(data, "/store/book/**") == {:ok, data["store"]["book"] }

      assert JSONPointer.get(data, "/**/nothing") == {:error, "token not found: nothing", []}

      assert_raise ArgumentError, "token not found: newspaper", fn -> JSONPointer.get!(data, "/**/newspaper") end
    end

    test "set" do
      assert JSONPointer.set(%{"a"=>1}, "/a", 2) == {:ok, %{"a" => 2}, 1 }
      assert JSONPointer.set(%{"a"=>%{"b"=>2}}, "/a/b", 3) == {:ok, %{"a" => %{"b" => 3}}, 2 }

      assert JSONPointer.set(%{}, "/a", 1) == {:ok, %{"a" => 1}, nil}
      assert JSONPointer.set(%{"a"=>1}, "/a", 6) == {:ok, %{"a" => 6}, 1}
      assert JSONPointer.set(%{}, "/a/b", 2) == {:ok, %{"a" => %{"b" => 2}}, nil}

      assert JSONPointer.set([], "/0", "first") == {:ok, ["first"], nil }
      assert JSONPointer.set([], "/1", "second") == {:ok, [nil, "second"], nil }
      assert JSONPointer.set([], "/0/test", "expected" ) == {:ok, [ %{"test" => "expected"}], nil }

      # NOTE: there is an argument that the below should raise, since it is intended that the first token
      # is referencing an array index. but it still works
      assert JSONPointer.set(%{}, "/0/test/0", "expected" ) == {:ok, %{"0" => %{"test" => ["expected"]}}, nil}
      assert JSONPointer.set([], "/0/test/1", "expected" ) == {:ok, [%{"test" => [nil, "expected"]}], nil }

    end

    test "remove" do
      assert JSONPointer.remove(%{"example"=>"hello"}, "/example") == {:ok, %{}, "hello"}
      assert JSONPointer.remove(%{"a"=>%{"b"=>5}}, "/a/b") == {:ok,%{"a" => %{}}, 5}
      assert JSONPointer.remove(%{"a"=>%{"b"=>%{"c"=>"discard"}}}, "/a/b/c") == {:ok, %{"a"=>%{"b"=>%{}}},"discard"}
      assert JSONPointer.remove(%{"a"=>%{"b"=>%{"c"=>"discard"}}}, "/a") == {:ok, %{}, %{"b" => %{"c" => "discard"}}}

      assert JSONPointer.remove(["alpha", "beta"], "/0") == {:ok, [nil,"beta"], "alpha"}
      assert JSONPointer.remove(["alpha", %{"beta"=>["c","d"]}], "/1/beta/0" ) == {:ok, ["alpha", %{"beta" => [nil, "d"]}], "c"}
    end

    test "has" do
      obj = %{
        "bla" => %{ "test" => "expected" },
        "foo" => [ ["hello"] ],
        "abc" => "bla"
      }

      assert JSONPointer.has(obj, "/bla") == true
      assert JSONPointer.has(obj, "/foo/0/0") == true
      assert JSONPointer.has(obj, "/bla/test") == true

      assert JSONPointer.has(obj, "/not-existing") == false
      assert JSONPointer.has(obj, "/not-existing/bla") == false
      assert JSONPointer.has(obj, "/test/1/bla") == false
      assert JSONPointer.has(obj, "/0") == false
      assert JSONPointer.has([], "/2") == false
      assert JSONPointer.has([], "/2/3") == false
    end

    test "parse" do
      assert JSONPointer.parse("") == { :ok, [] }
      assert JSONPointer.parse("invalid") == { :error, "invalid json pointer", "invalid" }
      assert JSONPointer.parse("/some/where/over") == { :ok, [ "some", "where", "over" ] }
      assert JSONPointer.parse("/hello~0bla/test~1bla") == { :ok, ["hello~bla","test/bla"] };
      assert JSONPointer.parse("/~2") == { :ok, ["**"] };
    end


    test "ensure_list_size" do
      assert JSONPointer.ensure_list_size([], 3) == [nil, nil, nil]
    end


  end
