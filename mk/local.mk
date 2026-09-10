# mk/local.mk: the consumer hook of this repository (MK-LOCAL).
# sync never touches this file.

# The full test tier set of make test. The unit tests join the set
# when the code lands.
TEST_GLOBS	= t/ci/*.t
