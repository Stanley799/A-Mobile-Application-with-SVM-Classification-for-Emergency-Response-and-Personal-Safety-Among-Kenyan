import os, sys
_ML = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "ml", "scripts")
if _ML not in sys.path:
    sys.path.insert(0, _ML)
