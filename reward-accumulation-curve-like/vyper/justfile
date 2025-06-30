set dotenv-load := true

format:
    uv run ruff check --select I --fix
    uv run mamushi src/

get-abi abi_address name:
    mox explorer get {{abi_address}} --save --name {{name}} --api-key $ETHERSCAN_API_KEY

test name:
    mox test -k {{name}} -s

test-a:
    mox test -s