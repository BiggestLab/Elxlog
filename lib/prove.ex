defmodule Elxlog.Worker do
  def prove_all do
    receive do
      {sender, {x, env, def, n}} -> send(sender, {:answer, [x, Elxlog.Prove.prove(x, [], env, def, n)]})
    end
  end
end

# ----------------prove-----------------------------------
defmodule Elxlog.Prove do
  @moduledoc """
  Prove Horn clause with SLD resolution
  """

  @doc """
  Return value is tuple. {val,env,def}
  prove([predicate, y, env, def, n)
  y is succeeding predicate(s)
  env is environment. It is keyword-list
  n is nest level. Alpha conversion uses n to generate new variable.
  ## example
  iex>Elxlog.Prove.prove([:builtin,[:true]],[],[],[],0)
  {true,[],[]}
  iex>Elxlog.Prove.prove([:builtin,[:fail]],[],[],[],0)
  {false,[],[]}
  """
  def prove([:pred, x], y, env, def, n) do
    if Elxcomp.is_compiled([:pred, x]) do
      Elxcomp.prove_builtin(x, y, env, def, n)
    else
      [name | _] = x
      def1 = def[name]
      prove_pred([:pred, x], def1, y, env, def, n)
    end
  end

  def prove([:builtin, x], y, env, def, n) do
    prove_builtin(x, y, env, def, n)
  end

  @doc """
  prove_all/4 work with prove/5
  """
  def prove_all([], env, def, _) do
    {true, env, def}
  end

  def prove_all([x | xs], env, def, n) do
    prove(x, xs, env, def, n)
  end

  @doc """
  prove_pred/6 is for predicate
  x is goal to prove
  d is set of difinition
  y is succeeding goals
  env is environment for variables
  n is nest lebel
  """
  # when d is nil result is fail
  def prove_pred(_, nil, _, env, def, _) do
    {false, env, def}
  end

  # when d is [] result is fail
  def prove_pred(_, [], _, env, def, _) do
    {false, env, def}
  end

  def prove_pred(x, [d | ds], y, env, def, n) do
    d1 = alpha_conv(d, n)
    trace(d1, env, def, n, "try ")

    if Elxlog.is_pred(d1) do
      env1 = unify(x, d1, env)

      if env1 != false do
        {res, env2, def} = prove_all(y, env1, def, n + 1)

        if res == true do
          trace(d1, env2, def, n, "succ")
          {res, env2, def}
        else
          prove_pred(x, ds, y, env, def, n)
        end
      else
        prove_pred(x, ds, y, env, def, n)
      end
    else
      if Elxlog.is_clause(d1) do
        env1 = unify(x, head(d1), env)

        if env1 != false do
          {res, env2, def} = prove_all(body(d1) ++ y, env1, def, n + 1)

          if res == true do
            trace(d1, env2, def, n, "succ")
            {res, env2, def}
          else
            trace(d1, env1, def, n, "fail")
            prove_pred(x, ds, y, env, def, n)
          end
        else
          trace(d1, env, def, n, "fail")
          prove_pred(x, ds, y, env, def, n)
        end
      end
    end
  end

  @doc """
  when trace is true in def print trace data
  n is nest lebel
  action [try,succ,fail]
  """
  def trace(x, env, def, n, action) do
    if def[:trace] == true do
      IO.write(n)
      IO.write(" ")
      IO.write(action)
      IO.write(" ")
      Elxlog.Print.print1(deref(x, env))
      trace1(env, def)
    end
  end

  def trace1(env, def) do
    msg = IO.gets("")

    if msg == "\n" do
      true
    else
      if msg == "e\n" do
        Elxlog.Print.print_env(env)
        trace1(env, def)
      else
        if msg == "l\n" do
          n = def[:"%last"]
          IO.write("last clause number is ")
          IO.puts(n)
        else
          if msg == "?\n" do
            IO.puts("enter -> next prove")
            IO.puts("e -> print environment")
            IO.puts("l -> print last clause number")
            IO.puts("? -> help")
          else
            trace1(env, def)
          end
        end
      end
    end
  end

  # builtin predicate
  def prove_builtin([:append | args], y, env, def, n) do
    try do
      # append([], Xs, Xs).
      env1 = unify(args, [[], {:Xs, n}, {:Xs, n}], env)

      if env1 != false do
        {result1, env1a, _} = prove_all(y, env1, def, n + 1)

        if result1 == true do
          throw({true, env1a, def})
        end
      end

      # append([X | Ls], Ys, [X | Zs]) :- append(Ls, Ys, Zs).
      env2 = unify(args, [[{:X, n} | {:Ls, n}], {:Ys, n}, [{:X, n} | {:Zs, n}]], env)

      if env2 != false do
        {result2, env2a, _} =
          prove([:builtin, [:append, {:Ls, n}, {:Ys, n}, {:Zs, n}]], y, env2, def, n + 1)

        if result2 == true do
          throw({true, env2a, def})
        end
      end

      {false, env, def}
    catch
      x -> x
    end
  end

  def prove_builtin([:member | args], y, env, def, n) do
    try do
      # member(X, [X | Ls]).
      env1 = unify(args, [{:X, n}, [{:X, n} | {:Ls, n}]], env)

      if env1 != false do
        {result, env2, def2} = prove_all(y, env1, def, n + 1)

        if result == true do
          throw({true, env2, def2})
        end
      end

      # member(X, [Y | Ls]) :- member(X, Ls).
      env2 = unify(args, [{:X, n}, [{:Y, n} | {:Ls, n}]], env)

      if env2 != false do
        {result, env3, def3} =
          prove([:builtin, [:member, {:X, n}, {:Ls, n}]], y, env2, def, n + 1)

        if result == true do
          throw({true, env3, def3})
        end
      end

      {false, env, def}
    catch
      x -> x
    end
  end

  def prove_builtin([:arg, a, b, c], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)

    if !Elxlog.is_compound(b1) do
      Elxlog.error("Error: arg not compound", [b])
    end

    [_, [_ | arg]] = b1

    cond do
      !is_integer(a1) ->
        Elxlog.error("Error: arg not in domain ", [a1])

      a1 > length(arg) || a1 <= 0 ->
        Elxlog.error("Error: arg not in domain ", [a1])

      true ->
        nil
    end

    env1 = unify(c, Enum.at(arg, a1 - 1), env)

    if env1 != false do
      prove_all(y, env1, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:ask], y, env, def, n) do
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:ask | vars], y, env, def, n) do
    ask(vars, env)
    ans = IO.gets("")

    cond do
      ans == ".\n" -> {true, env, def}
      ans == ";\n" -> {false, env, def}
      true -> prove_all(y, env, def, n + 1)
    end
  end

  def prove_builtin([:atom, x], y, env, def, n) do
    x1 = deref(x, env)

    if is_atom(x1) && !Elxlog.is_var(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:atomic, x], y, env, def, n) do
    x1 = deref(x, env)

    if (is_atom(x1) && !Elxlog.is_var(x1)) || is_number(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:between, a, b, c], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)

    if a1 > b1 do
      {false, env, def}
    else
      env1 = unify(c, a1, env)

      if prove_all(y, env1, def, n + 1) == true do
        {true, env1, def}
      else
        prove_builtin([:between, a1 + 1, b1, c], y, env, def, n)
      end
    end
  end

  @doc """
  system builtin predicate for developer
  """
  def prove_builtin([:debug], y, env, def, n) do
    debug(def, [])
    prove_all(y, env, def, n + 1)
  end

  @doc """
  evaluate native Elixir function
  change from function of elxlog to string. and eval as Elixir function
  """
  def prove_builtin([:elixir, [:func, x]], y, env, def, n) do
    {x1, _} = deref(x, env) |> func_to_str() |> Code.eval_string([], __ENV__)

    if x1 == true do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:parallel | x], y, env, def, n) do
    if def[:parallel] == false do
      prove_all(x ++ y, env, def, n)
    else
      parallel1(x, env, def, n)
      x1 = parallel2(length(x), [])

      if Enum.any?(x1, fn x -> x == false end) do
        {false, env, def}
      else
        env1 = flatten_env(x1) ++ env
        prove_all(y, env1, def, n)
      end
    end
  end

  def prove_builtin([:fail], _, env, def, _) do
    {false, env, def}
  end

  def prove_builtin([:float, x], y, env, def, n) do
    x1 = deref(x, env)

    if is_float(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:functor, a, b, c], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)
    c1 = deref(c, env)

    cond do
      Elxlog.is_compound(a1) ->
        [_, [name | arg]] = a1
        env1 = unify(b, name, env)
        env2 = unify(c, length(arg), env1)

        if env1 != false && env2 != false do
          prove_all(y, env2, def, n + 1)
        else
          {false, env, def}
        end

      Elxlog.is_var(a1) && (is_atom(b1) && !Elxlog.is_var(b1)) && is_integer(c1) ->
        env1 = unify(a, [:pred, [b1 | make_list(c1)]], env)
        prove_all(y, env1, def, n + 1)

      Elxlog.is_compound(a1) && (is_atom(b1) && !Elxlog.is_var(b1)) && is_integer(c1) ->
        [_, [name | arg]] = a1

        if name == b1 && length(arg) == c1 do
          prove_all(y, env, def, n + 1)
        else
          {false, env, def}
        end

      true ->
        {false, env, def}
    end
  end

  def prove_builtin([:halt], _, _, _, _) do
    throw("goodbye")
  end

  def prove_builtin([:integer, x], y, env, def, n) do
    x1 = deref(x, env)

    if is_integer(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:is, a, b], y, env, def, n) do
    b1 = eval(deref(b, env), env)

    if !is_number(b1) do
      Elxlog.error("Error: illegal formula ", [b])
    end

    env1 = unify(a, b1, env)

    if env1 != false do
      prove_all(y, env1, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:listing], y, env, def, n) do
    listing(Enum.reverse(def), [])
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:listing, a], y, env, def, n) do
    def[a] |> listing1()
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:length, a, b], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)

    cond do
      is_list(a1) && Elxlog.is_var(b1) ->
        env1 = unify(length(a1), b, env)
        prove_all(y, env1, def, n + 1)

      Elxlog.is_var(a1) && is_integer(b1) ->
        env1 = unify(a1, make_list(b1), env)
        prove_all(y, env1, def, n + 1)

      is_list(a1) && is_integer(b1) ->
        if length(a1) == b1 do
          prove_all(y, env, def, n + 1)
        else
          {false, env, def}
        end

      true ->
        {false, env, def}
    end
  end

  def prove_builtin([:name, a, b], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)

    cond do
      is_atom(a1) && !Elxlog.is_var(a1) && Elxlog.is_var(b1) ->
        env1 = unify(b1, Atom.to_charlist(a1), env)
        prove_all(y, env1, def, n + 1)

      Elxlog.is_var(a1) && is_list(b1) ->
        b2 = b1 |> to_string() |> String.to_atom()
        env1 = unify(a1, b2, env)
        prove_all(y, env1, def, n + 1)

      is_atom(a1) && is_list(b1) ->
        b2 = b1 |> to_string() |> String.to_atom()

        if a1 == b2 do
          prove_all(y, env, def, n + 1)
        else
          {false, env < def}
        end

      true ->
        {false, env, def}
    end
  end

  def prove_builtin([:nl], y, env, def, n) do
    IO.puts("")
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:nonvar, x], y, env, def, n) do
    x1 = deref(x, env)

    if !Elxlog.is_var(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:not, a], y, env, def, n) do
    {res, _, _} = prove(a, y, env, def, n)

    if res == true do
      {false, env, def}
    else
      prove_all(y, env, def, n + 1)
    end
  end

  def prove_builtin([:notrace], y, env, def, n) do
    def1 = Keyword.put(def, :trace, false)
    prove_all(y, env, def1, n + 1)
  end

  def prove_builtin([:number, x], y, env, def, n) do
    x1 = deref(x, env)

    if is_number(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:reconsult, x], y, env, _, n) do
    fname = Atom.to_string(x)
    [_, ext] = String.split(fname, ".")

    if ext == "pl" do
      {status, string} = File.read(fname)

      if status == :error do
        Elxlog.error("Error: reconsult", [])
      end

      codelist = String.split(string, "!elixir")
      buf = hd(codelist) |> Elxlog.Read.tokenize(:filein)
      def1 = reconsult(buf, [])

      if length(codelist) == 2 do
        [_, elixir] = codelist
        Code.compiler_options(ignore_module_conflict: true)
        Code.compile_string("defmodule Elxfunc do\n" <> elixir <> "end\n")
      end

      prove_all(y, env, def1, n + 1)
    else
      if ext == "o" do
        {status, string} = File.read(fname)

        if status == :error do
          Elxlog.error("Error: reconsult", [])
        end

        Code.compiler_options(ignore_module_conflict: true)
        Code.compile_string(string)
        prove_all(y, env, [], n + 1)
      end
    end
  end

  def prove_builtin([:compile, x], y, env, _, n) do
    {status, string} = File.read(Atom.to_string(x))

    if status == :error do
      Elxlog.error("Error: compile", [])
    end

    codelist = String.split(string, "!elixir")
    buf = hd(codelist) |> Elxlog.Read.tokenize(:filein)
    def1 = reconsult(buf, []) |> Enum.reverse()

    if length(codelist) == 2 do
      [_, elixir] = codelist
      Compile.compile(x, def1, elixir)
      prove_all(y, env, [], n + 1)
    else
      elixir = ""
      Compile.compile(x, def1, elixir)
      prove_all(y, env, [], n + 1)
    end
  end

  def prove_builtin([:read, x], y, env, def, n) do
    x1 = deref(x, env)
    {s, _} = Elxlog.Read.parse([], :stdin)
    env1 = unify(x1, s, env)
    prove_all(y, env1, def, n + 1)
  end

  def prove_builtin([:time, x], y, env, def, n) do
    {time, {res, env1, _}} = :timer.tc(fn -> prove(x, [], env, def, n) end)
    IO.inspect("time: #{time} micro second")

    if res == true do
      prove_all(y, env1, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:trace], y, env, def, n) do
    def1 = Keyword.put(def, :trace, true)
    prove_all(y, env, def1, n + 1)
  end

  def prove_builtin([true], y, env, def, n) do
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:var, x], y, env, def, n) do
    x1 = deref(x, env)

    if Elxlog.is_var(x1) do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:write, x], y, env, def, n) do
    x1 = deref(x, env)
    Elxlog.Print.print1(x1)
    prove_all(y, env, def, n + 1)
  end

  def prove_builtin([:=, a, b], y, env, def, n) do
    env1 = unify(a, b, env)

    if env1 == false do
      {false, env, def}
    else
      prove_all(y, env1, def, n + 1)
    end
  end

  def prove_builtin([:>, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 > b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:>=, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 >= b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:<, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 < b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:<=, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 <= b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:!=, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 != b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:==, a, b], y, env, def, n) do
    a1 = eval(a, env)
    b1 = eval(b, env)

    if a1 == b1 do
      prove_all(y, env, def, n + 1)
    else
      {false, env, def}
    end
  end

  def prove_builtin([:"=..", a, b], y, env, def, n) do
    a1 = deref(a, env)
    b1 = deref(b, env)

    if Elxlog.is_var(a1) do
      env1 = unify(a1, [:pred, b1], env)
      prove_all(y, env1, def, n + 1)
    else
      [_, x] = a1
      env1 = unify(x, b1, env)
      prove_all(y, env1, def, n + 1)
    end
  end

  def prove_builtin(x, _, _, _, _) do
    IO.inspect(x)
    throw("Error: not exist builtin")
  end

  @doc """
  eval/2 is for is builtin predicate
  evaluate formula
  formula  e.g.  [:formula,[:+,x,y]]
  """
  def eval(x, _) when is_number(x) do
    x
  end

  def eval(x, env) when is_atom(x) do
    x1 = deref(x, env)

    if x == x1 do
      Elxlog.error("Error: eval ununified ", [x])
    else
      x1
    end
  end

  def eval([:formula, x], env) do
    eval(x, env)
  end

  def eval([:func, x], env) do
    {x1, _} = Code.eval_string(func_to_str(x), [], __ENV__)
    eval(x1, env)
  end

  def eval([:+, x, y], env) do
    eval(x, env) + eval(y, env)
  end

  def eval([:-, x, y], env) do
    eval(x, env) - eval(y, env)
  end

  def eval([:*, x, y], env) do
    eval(x, env) * eval(y, env)
  end

  def eval([:/, x, y], env) do
    eval(x, env) / eval(y, env)
  end

  def eval([:^, x, y], env) do
    x1 = eval(x, env)
    y1 = eval(y, env)

    if is_float(x1) || is_float(y1) || y1 < 0 do
      :math.pow(x1, y1)
    else
      power(x1, y1)
    end
  end

  def eval(x, env) do
    deref(x, env)
  end

  def power(x, y) do
    cond do
      y == 0 -> 1
      rem(y, 2) == 0 -> power(x * x, div(y, 2))
      true -> x * power(x, y - 1)
    end
  end

  @doc """
  for builtin elixir predicate
  add prefix "Elxfunc"
  """
  def func_to_str([name | args]) do
    (["Elxfunc."] ++ [Atom.to_string(name)] ++ [list_to_str(args)]) |> Enum.join()
  end

  @doc """
  for builtin predicate "elixir"
  change from elxlog data to string
  """
  def list_to_str(x) do
    ["("] ++ list_to_str1(x) ++ [")"]
  end

  def list_to_str1([]) do
    [""]
  end

  def list_to_str1([x]) do
    cond do
      is_integer(x) -> [Integer.to_string(x)]
      is_float(x) -> [Float.to_string(x)]
      is_atom(x) -> [Atom.to_string(x)]
      is_list(x) -> [list_to_str2(x)]
    end
  end

  def list_to_str1([x | xs]) do
    cond do
      is_integer(x) -> [Integer.to_string(x)] ++ [","] ++ list_to_str1(xs)
      is_float(x) -> [Float.to_string(x)] ++ [","] ++ list_to_str1(xs)
      is_atom(x) -> [Atom.to_string(x)] ++ [","] ++ list_to_str1(xs)
      is_list(x) -> [list_to_str2(x) ++ [","] ++ list_to_str1(xs)]
    end
  end

  def list_to_str2([]) do
    ["[]"]
  end

  def list_to_str2(x) do
    ["["] ++ list_to_str1(x) ++ ["]"]
  end

  @doc """
  help function for parallel/n
  """
  def parallel1([], _, _, _) do
    []
  end

  def parallel1([x | xs], env, def, n) do
    pid = spawn(Elxlog.Worker, :prove_all, [])
    def1 = Keyword.put(def, :parallel, false)
    send(pid, {self(), {x, env, def1, n}})
    parallel1(xs, env, def, n)
  end

  def parallel2(0, res) do
    res
  end

  def parallel2(c, res) do
    receive do
      {:answer, ls} ->
        [[_, goal], {result, env, _}] = ls

        if result == false do
          parallel2(c - 1, [false | res])
        else
          env1 = compress_env(goal, env)
          parallel2(c - 1, [env1 | res])
        end
    end
  end

  def compress_env([], _) do
    []
  end

  def compress_env([v | vs], env) do
    v1 = deref(v, env)

    if Elxlog.is_var(v) do
      if v != v1 do
        [[v, v1] | compress_env(vs, env)]
      else
        [[v, :error] | compress_env(vs, env)]
      end
    else
      compress_env(vs, env)
    end
  end

  def flatten_env([]) do
    []
  end

  def flatten_env([e | es]) do
    e ++ flatten_env(es)
  end

  @doc """
  for predicate ask/0
  ask prints variables of goal
  """
  def ask([], _) do
    true
  end

  def ask([x], env) do
    IO.write(x)
    IO.write(" = ")
    Elxlog.Print.print1(deref(x, env))
  end

  def ask([x | xs], env) do
    IO.write(x)
    IO.write(" = ")
    Elxlog.Print.print(deref(x, env))
    ask(xs, env)
  end

  @doc """
  for builtin reconsult/1
  parse file text and add difinition
  """
  def reconsult([], def) do
    def
  end

  def reconsult(buf, def) do
    {s, buf1} = Elxlog.Read.parse(buf, :filein)

    if Elxlog.is_pred(s) do
      [_, [name | _]] = s
      def1 = find_def(def, name)
      def2 = Keyword.put(def, name, def1 ++ [s])
      reconsult(buf1, def2)
    else
      # clause
      [_, [_, [name | _]], _] = s
      def1 = find_def(def, name)
      def2 = Keyword.put(def, name, def1 ++ [s])
      reconsult(buf1, def2)
    end
  end

  @doc """
  for builtin listing/0 /1
  """
  def listing([], _) do
    true
  end

  def listing([{key, body} | rest], check) do
    if Enum.member?(check, key) do
      listing(rest, check)
    else
      listing1(body)
      listing(rest, [key | check])
    end
  end

  def listing1(nil) do
    true
  end

  def listing1([]) do
    true
  end

  def listing1([x | xs]) do
    Elxlog.Print.print(x)
    listing1(xs)
  end

  @doc """
  make list [:_,:_,...] size n
  """
  def make_list(0) do
    []
  end

  def make_list(n) do
    [:_ | make_list(n - 1)]
  end

  def debug([], _) do
    true
  end

  def debug([{key, body} | rest], check) do
    if Enum.member?(check, key) do
      debug(rest, check)
    else
      debug1(body)
      debug(rest, [key | check])
    end
  end

  def debug1([]) do
    true
  end

  def debug1([x | xs]) do
    Elxlog.Print.print_debug(x)
    debug1(xs)
  end

  def find_def(ls, name) do
    def = ls[name]

    if def == nil do
      []
    else
      def
    end
  end

  # dereference
  def deref(x, _) when is_number(x) do
    x
  end

  def deref(x, env) when is_atom(x) do
    x1 = deref1(x, env, env)

    if x1 == false do
      x
    else
      deref(x1, env)
    end
  end

  def deref({x, n}, env) when is_atom(x) do
    x1 = deref1({x, n}, env, env)

    if x1 == false do
      {x, n}
    else
      deref(x1, env)
    end
  end

  def deref([:func, x], env) do
    [:func, deref(x, env)]
  end

  def deref([:pred, x], env) do
    [:pred, deref(x, env)]
  end

  def deref([:builtin, x], env) do
    [:builtin, deref(x, env)]
  end

  def deref([], _) do
    []
  end

  def deref([x | xs], env) when is_list(x) do
    [deref(x, env) | deref(xs, env)]
  end

  def deref([x | xs], env) do
    x1 = deref1(x, env, env)

    if x1 == false do
      [x | deref(xs, env)]
    else
      [x1 | deref(xs, env)]
    end
  end

  def deref1(_, [], _) do
    false
  end

  def deref1(x, [[x, v] | _], env) do
    if !Elxlog.is_var(v) do
      v
    else
      deref1(v, env, env)
    end
  end

  def deref1(x, [_ | es], env) do
    deref1(x, es, env)
  end

  # clause head
  def head([:clause, h, _]) do
    h
  end

  # clause body
  def body([:clause, _, b]) do
    b
  end

  # alpha convert :X -> {:X,n}
  def alpha_conv([], _) do
    []
  end

  def alpha_conv(x, _) when is_number(x) do
    x
  end

  def alpha_conv(x, n) when is_atom(x) do
    if Elxlog.is_atomvar(x) do
      {x, n}
    else
      x
    end
  end

  def alpha_conv([x | y], n) when is_atom(x) do
    if Elxlog.is_atomvar(x) do
      [{x, n} | alpha_conv(y, n)]
    else
      [x | alpha_conv(y, n)]
    end
  end

  def alpha_conv([x | y], n) when is_number(x) do
    [x | alpha_conv(y, n)]
  end

  def alpha_conv([x | y], n) when is_list(x) do
    [alpha_conv(x, n) | alpha_conv(y, n)]
  end

  # unification
  def unify([], [], env) do
    env
  end

  @doc """
  unificate x and y
  env is environment. e.g. [[{:X,1},{:Y,2}],[{:Y,2},3]
  old variable is always left side in each environment element
  """
  def unify([x | xs], [y | ys], env) do
    # IO.inspect binding()
    x1 = deref(x, env)
    y1 = deref(y, env)

    cond do
      Elxlog.is_anonymous(x1) || Elxlog.is_anonymous(y1) -> unify(xs, ys, env)
      Elxlog.is_var(x1) && !Elxlog.is_var(y1) -> unify(xs, ys, [[x1, y1] | env])
      !Elxlog.is_var(x1) && Elxlog.is_var(y1) -> unify(xs, ys, [[y1, x1] | env])
      Elxlog.is_var(x1) && Elxlog.is_var(y1) && older(x1, y1) -> unify(xs, ys, [[x1, y1] | env])
      Elxlog.is_var(x1) && Elxlog.is_var(y1) && older(y1, x1) -> unify(xs, ys, [[y1, x1] | env])
      x1 == [] && y1 != [] -> false
      x1 != [] && y1 == [] -> false
      is_list(x1) && is_list(y1) -> unify1(x1, y1, xs, ys, env)
      x1 == y1 -> unify(xs, ys, env)
      true -> false
    end
  end

  # atom or number
  def unify(x, y, env) do
    unify([x], [y], env)
  end

  def unify1(x, y, xs, ys, env) do
    env1 = unify(x, y, env)

    if env1 != false do
      unify(xs, ys, env1)
    else
      false
    end
  end

  def older(x, _) when is_atom(x) do
    true
  end

  def older(_, y) when is_atom(y) do
    false
  end

  def older({_, n1}, {_, n2}) do
    cond do
      n1 < n2 -> true
      true -> false
    end
  end
end
