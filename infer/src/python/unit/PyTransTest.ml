(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open! IStd
module F = Format

let sourcefile = Textual.SourceFile.create "dummy.py"

let run_test source =
  Py.initialize ~interpreter:Version.python_exe () ;
  let code = FFI.from_string ~source ~filename:"dummy" in
  Py.finalize () ;
  let res = PyTrans.to_module ~sourcefile (PyCommon.toplevel "main") code in
  F.printf "%a" Textual.Module.pp res


let%test_module "basic_tests" =
  ( module struct
    let%expect_test _ =
      let source = "x = 42" in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              store &$globals::x <- $builtins.python_int(42):*PyInt
              ret null

        }

        global $globals::x: *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source = {|
x = 42
print(x)
      |} in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              store &$globals::x <- $builtins.python_int(42):*PyInt
              n0:*PyObject = load &$globals::x
              n1 = $builtins.print(n0)
              ret null

        }

        global $globals::x: *PyObject

        declare $builtins.print(...) : *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source = {|
x = 42
y = 10
print(x + y)
      |} in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              store &$globals::x <- $builtins.python_int(42):*PyInt
              store &$globals::y <- $builtins.python_int(10):*PyInt
              n0:*PyObject = load &$globals::x
              n1:*PyObject = load &$globals::y
              n2 = $builtins.binary_add(n0, n1)
              n3 = $builtins.print(n2)
              ret null

        }

        global $globals::y: *PyObject

        global $globals::x: *PyObject

        declare $builtins.print(...) : *PyObject

        declare $builtins.binary_add(*PyObject, *PyObject) : *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]
  end )


let%test_module "top_level_calls" =
  ( module struct
    let%expect_test _ =
      let source =
        {|
# user-defined top level function
def my_fun(x, y):
        print(x)
        print(y)
        # local variable z
        z = x + y
        return z

a = 10
# global variable z
z = my_fun(42, a)
print(z)
      |}
      in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              n0 = $builtins.python_code("my_fun")
              store &$globals::a <- $builtins.python_int(10):*PyInt
              n1:*PyObject = load &$globals::a
              n2 = $toplevel::my_fun($builtins.python_int(42), n1)
              store &$globals::z <- n2:*PyObject
              n3:*PyObject = load &$globals::z
              n4 = $builtins.print(n3)
              ret null

        }

        define $toplevel::my_fun(x: *PyObject, y: *PyObject) : *PyObject {
          local z: *PyObject
          #b0:
              n0:*PyObject = load &x
              n1 = $builtins.print(n0)
              n2:*PyObject = load &y
              n3 = $builtins.print(n2)
              n4:*PyObject = load &x
              n5:*PyObject = load &y
              n6 = $builtins.binary_add(n4, n5)
              store &z <- n6:*PyObject
              n7:*PyObject = load &z
              ret n7

        }

        global $globals::z: *PyObject

        global $globals::a: *PyObject

        declare $builtins.python_code(*String) : *PyCode

        declare $builtins.print(...) : *PyObject

        declare $builtins.binary_add(*PyObject, *PyObject) : *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source =
        {|
# testing global python attribute
def update_global():
        global z
        z = z + 1

z = 0
update_global()
print(z)
      |}
      in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              n0 = $builtins.python_code("update_global")
              store &$globals::z <- $builtins.python_int(0):*PyInt
              n1 = $toplevel::update_global()
              n2:*PyObject = load &$globals::z
              n3 = $builtins.print(n2)
              ret null

        }

        define $toplevel::update_global() : *PyObject {
          #b0:
              n0:*PyObject = load &$globals::z
              n1 = $builtins.binary_add(n0, $builtins.python_int(1))
              store &$globals::z <- n1:*PyObject
              ret null

        }

        global $globals::z: *PyObject

        declare $builtins.python_code(*String) : *PyCode

        declare $builtins.print(...) : *PyObject

        declare $builtins.binary_add(*PyObject, *PyObject) : *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]
  end )


let%test_module "conditionals" =
  ( module struct
    let%expect_test _ =
      let source =
        {|
def coin():
    return False

def f(x, y):
    if coin():
          return x
    else:
          return y
      |}
      in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              n0 = $builtins.python_code("coin")
              n1 = $builtins.python_code("f")
              ret null

        }

        define $toplevel::f(x: *PyObject, y: *PyObject) : *PyObject {
          #b0:
              n0 = $toplevel::coin()
              jmp b1, b2

          #b1:
              prune $builtins.is_true(n0)
              n1:*PyObject = load &x
              ret n1

          #b2:
              prune $builtins.is_true(__sil_lnot(n0))
              n2:*PyObject = load &y
              ret n2

          #b3:
              ret null

        }

        define $toplevel::coin() : *PyObject {
          #b0:
              ret 0

        }

        declare $builtins.python_code(*String) : *PyCode

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source =
        {|
def coin():
    return False

def f(x, y):
    z = 0
    if coin():
          z = x
    else:
          z = y
    return z
      |}
      in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              n0 = $builtins.python_code("coin")
              n1 = $builtins.python_code("f")
              ret null

        }

        define $toplevel::f(x: *PyObject, y: *PyObject) : *PyObject {
          local z: *PyObject
          #b0:
              store &z <- $builtins.python_int(0):*PyInt
              n0 = $toplevel::coin()
              jmp b1, b2

          #b1:
              prune $builtins.is_true(n0)
              n1:*PyObject = load &x
              store &z <- n1:*PyObject
              jmp b3

          #b2:
              prune $builtins.is_true(__sil_lnot(n0))
              n2:*PyObject = load &y
              store &z <- n2:*PyObject
              jmp b3

          #b3:
              n3:*PyObject = load &z
              ret n3

        }

        define $toplevel::coin() : *PyObject {
          #b0:
              ret 0

        }

        declare $builtins.python_code(*String) : *PyCode

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source =
        {|
def coin():
    return False

def f(x, y):
    z = 0
    if coin():
          if coin():
            z = x
          else:
            return 1664
          z = z + 1
    else:
          z = z + 1
          if coin():
            return 42
          else:
            z = y
    return z
      |}
      in
      run_test source ;
      [%expect
        {|
        .source_language = "python"

        define $toplevel::main() : *PyObject {
          #b0:
              n0 = $builtins.python_code("coin")
              n1 = $builtins.python_code("f")
              ret null

        }

        define $toplevel::f(x: *PyObject, y: *PyObject) : *PyObject {
          local z: *PyObject
          #b0:
              store &z <- $builtins.python_int(0):*PyInt
              n0 = $toplevel::coin()
              jmp b1, b2

          #b1:
              prune $builtins.is_true(n0)
              n1 = $toplevel::coin()
              jmp b3, b4

          #b3:
              prune $builtins.is_true(n1)
              n2:*PyObject = load &x
              store &z <- n2:*PyObject
              jmp b5

          #b4:
              prune $builtins.is_true(__sil_lnot(n1))
              ret $builtins.python_int(1664)

          #b5:
              n3:*PyObject = load &z
              n4 = $builtins.binary_add(n3, $builtins.python_int(1))
              store &z <- n4:*PyObject
              jmp b6

          #b2:
              prune $builtins.is_true(__sil_lnot(n0))
              n5:*PyObject = load &z
              n6 = $builtins.binary_add(n5, $builtins.python_int(1))
              store &z <- n6:*PyObject
              n7 = $toplevel::coin()
              jmp b7, b8

          #b7:
              prune $builtins.is_true(n7)
              ret $builtins.python_int(42)

          #b8:
              prune $builtins.is_true(__sil_lnot(n7))
              n8:*PyObject = load &y
              store &z <- n8:*PyObject
              jmp b6

          #b6:
              n9:*PyObject = load &z
              ret n9

        }

        define $toplevel::coin() : *PyObject {
          #b0:
              ret 0

        }

        declare $builtins.python_code(*String) : *PyCode

        declare $builtins.binary_add(*PyObject, *PyObject) : *PyObject

        declare $builtins.python_tuple(...) : *PyObject

        declare $builtins.python_string(*String) : *PyString

        declare $builtins.python_int(int) : *PyInt |}]


    let%expect_test _ =
      let source = {|
def foo(x):
    pass

def f(x):
    foo(1 if x else 0)
      |} in
      run_test source ;
      [%expect
        {|
      .source_language = "python"

      define $toplevel::main() : *PyObject {
        #b0:
            n0 = $builtins.python_code("foo")
            n1 = $builtins.python_code("f")
            ret null

      }

      define $toplevel::f(x: *PyObject) : *PyObject {
        #b0:
            n0:*PyObject = load &x
            n1:*PyObject = load &$globals::foo
            jmp b1(n1), b2(n1)

        #b1(n2: *PyObject):
            prune $builtins.is_true(n0)
            jmp b3($builtins.python_int(1), n2)

        #b2(n3: *PyObject):
            prune $builtins.is_true(__sil_lnot(n0))
            jmp b3($builtins.python_int(0), n3)

        #b3(n4: *PyInt, n5: *PyObject):
            n6 = $builtins.python_call(n5, n4)
            ret null

      }

      define $toplevel::foo(x: *PyObject) : *PyObject {
        #b0:
            ret null

      }

      declare $builtins.python_code(*String) : *PyCode

      declare $builtins.python_call(...) : *PyObject

      declare $builtins.python_tuple(...) : *PyObject

      declare $builtins.python_string(*String) : *PyString

      declare $builtins.python_int(int) : *PyInt |}]
  end )