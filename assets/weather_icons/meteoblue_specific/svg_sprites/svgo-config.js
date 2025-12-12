// inline all styles, even if used multiple times and then remove the style element
module.exports = {
    plugins: [
        {
            name: 'preset-default',
            params: {
                overrides: {
                    inlineStyles: {
                        onlyMatchedOnce: false,
                    },
                },
            },
        },
        'removeStyleElement',
    ],
};
