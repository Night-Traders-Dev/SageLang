import arrays

proc main():
    let arr = [1, 2, 3, 4, 5]
    print slice(arr, 0, -1)
    print slice(arr, 0, 0)
    print slice(arr, 0, 10)

main()
