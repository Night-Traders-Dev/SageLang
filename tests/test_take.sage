import arrays

proc main():
    let arr = [1, 2, 3, 4, 5]
    print arrays.take(arr, 3)
    print arrays.take(arr, 0)
    print arrays.take(arr, -1)
    print arrays.take(arr, -5)
    print arrays.take(arr, 10)

main()
