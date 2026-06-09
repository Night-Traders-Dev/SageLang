# EXPECT_ERROR: error: expected ':' after if condition, found end of line
# EXPECT_ERROR: parser_missing_colon.sage:4:8
# EXPECT_ERROR: help: add ':' before the end of the line to start the block
if true
    print 1
