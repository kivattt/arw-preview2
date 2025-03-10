package load_image

import "core:testing"

@(test)
test_wrap :: proc(t: ^testing.T) {
    result: int

    result = wrap(10, 20)
    if result != 10 {
        testing.fail(t)
    }

    result = wrap(69, 69)
    if result != 0 {
        testing.fail(t)
    }

    result = wrap(-1, 20)
    if result != 19 {
        testing.fail(t)
    }

    result = wrap(-40, 20)
    if result != 0 {
        testing.fail(t)
    }
}