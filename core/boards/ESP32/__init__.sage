## SageLang ESP32 board package (classic ESP32, e.g. ESP32-D0WD-V3).
##
##   import esp32
##   print esp32.describe()
##
## Run from the repo root with the library on the search path:
##   SAGE_PATH=core/lib ./core/sage core/boards/ESP32/test_smoke.sage

import esp32

from esp32 import describe
from esp32 import pin_valid
from esp32 import pin_can_output
from esp32 import pin_is_strapping
from esp32 import flash_offset
