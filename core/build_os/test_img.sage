import os.image.diskimg as diskimg
let img = diskimg.create_gpt_image(1)
diskimg.save_image(img, "test.img")
print("OK")
