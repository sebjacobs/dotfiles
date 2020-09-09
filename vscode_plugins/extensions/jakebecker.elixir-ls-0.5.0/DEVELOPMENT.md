## Packaging

Make and push the elixir-ls tag
Update the elixir-ls submodule `git submodule foreach git pull origin master`

Test the new vscode-elixir-ls version with:

```
npm install -g vsce@latest
vsce package
code --install-extension ./elixir-ls-0.2.44.vsix  --force
```

- Ensure you have a clean git repository
- `vsce publish 0.3.1` (or whatever version) (note that this will create a commit and a tag)
- `git push upstream --tags`
- Update the release on github with the elixir-ls.zip file
- Update forum announcement post: https://elixirforum.com/t/introducing-elixirls-the-elixir-language-server/5857

## References

https://code.visualstudio.com/api/working-with-extensions/publishing-extension

Personal Access Token (PAT) direct link: https://dev.azure.com/elixir-lsp/_usersSettings/tokens

https://code.visualstudio.com/api/language-extensions/embedded-languages

## VSCode

Run "Developer: Inspect Editor Tokens and Scopes" when you want to debug the textmate grammar
