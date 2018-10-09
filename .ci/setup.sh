OPENRESTY_DOWNLOAD_DIR=$DOWNLOAD_CACHE/openresty-$V_OPENRESTY
LUAROCKS_DOWNLOAD_DIR=$DOWNLOAD_CACHE/luarocks-$V_LUAROCKS

mkdir -p $OPENRESTY_DOWNLOAD_DIR $LUAROCKS_DOWNLOAD_DIR

if [ ! $(ls -A $OPENRESTY_DOWNLOAD_DIR) ]; then
    pushd $DOWNLOAD_CACHE
    wget https://openresty.org/download/openresty-$V_OPENRESTY.tar.gz
    tar xzf openresty-$V_OPENRESTY.tar.gz
    popd
fi

if [ ! $(ls -A $LUAROCKS_DOWNLOAD_DIR) ]; then
    pushd $DOWNLOAD_CACHE
    wget http://luarocks.github.io/luarocks/releases/luarocks-$V_LUAROCKS.tar.gz
    tar xzf luarocks-$V_LUAROCKS.tar.gz
    popd
fi

OPENRESTY_INSTALL_DIR=$INSTALL_CACHE/openresty-$V_OPENRESTY
LUAROCKS_INSTALL_DIR=$INSTALL_CACHE/luarocks-$V_LUAROCKS

mkdir -p $OPENRESTY_INSTALL_DIR $LUAROCKS_INSTALL_DIR

if [ ! "$(ls -A $OPENRESTY_INSTALL_DIR)" ]; then
    pushd $OPENRESTY_DOWNLOAD_DIR
    ./configure \
        --prefix=$OPENRESTY_INSTALL_DIR \
        --with-http_v2_module \
        &> build.log || (cat build.log && exit 1)

    make &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
    popd

    git clone https://github.com/tokers/lua-resty-http2
    cp -r lua-resty-http2/lib/resty/http2 $OPENRESTY_INSTALL_DIR/lualib/resty
    cp lua-resty-http2/lib/resty/http2.lua /usr/local/openresty/lualib/resty
    rm -rf lua-resty-http2
fi

if [ ! "$(ls -A $LUAROCKS_INSTALL_DIR)" ]; then
    pushd $LUAROCKS_DOWNLOAD_DIR
    ./configure \
        --prefix=$LUAROCKS_INSTALL_DIR \
        --lua-suffix=jit \
        --with-lua=$OPENRESTY_INSTALL_DIR/luajit \
        --with-lua-include=$OPENRESTY_INSTALL_DIR/luajit/include/luajit-2.1 \
        &> build.log || (cat build.log && exit 1)

    make build &> build.log || (cat build.log && exit 1)
    make install &> build.log || (cat build.log && exit 1)
    popd
fi

export PATH=$PATH:$OPENRESTY_INSTALL_DIR/nginx/sbin:$OPENRESTY_INSTALL_DIR/bin:$LUAROCKS_INSTALL_DIR/bin

eval `luarocks path`
