type X = {
    foo(s : String) -> String
}

var x : X := object {
    method foo(s : String) -> String {
        s
    }
}
def y : String = x.foo(3)
print(y)

