python3 -c "import crypt; print(crypt.crypt(input('clear-text pw: '), crypt.mksalt(crypt.METHOD_SHA512)))"
