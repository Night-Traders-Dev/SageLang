import glob
for f in glob.glob("core/lib/transpiler/**/*.sage", recursive=True):
    with open(f, "r") as fp: text = fp.read()
    
    import re
    # Remove `: Type` from parameters
    text = re.sub(r'([a-zA-Z_0-9]+):\s*[a-zA-Z_0-9\[\]]+', r'\1', text)
    # Remove `-> Type` from return signatures
    text = re.sub(r'->\s*[a-zA-Z_0-9\[\]]+:', r':', text)
    
    with open(f, "w") as fp: fp.write(text)
