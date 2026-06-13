import net.url as url
import assert

proc test_decode():
    assert.assert_equal(url.decode("%20"), " ", "Space decode failed")
    assert.assert_equal(url.decode("a+b"), "a b", "Plus decode failed")
    assert.assert_equal(url.decode("%"), "%", "Trailing % failed")
    assert.assert_equal(url.decode("%1"), "%1", "Incomplete %1 failed")
    assert.assert_equal(url.decode("%1g"), "%1g", "Invalid hex failed")
    assert.assert_equal(url.decode("abc%21def"), "abc!def", "Middle % decode failed")
    print("URL decode tests passed")

test_decode()
