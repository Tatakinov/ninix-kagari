# How to contribute

## バグ報告/Bug report

// TODO stub

## 機能の要望/Feature request

// TODO stub

## Pull Request

1. fork ninix-kagari

2. set up a new branch

```bash
git clone https://github.com/your_name/ninix-kagari
cd ninix-kagari
git switch develop
git switch -c new_branch
```

`new_branch` should take the following form.

- `fix/surface_is_not_displayed`

- `feature/implement_c_tag`

3. modify the code

About coding style:

- indent: two space, not tab

- curly braces: use only when creating a Hash, do not use in lambda or block

- logical operator: use `not`, `and` and/or `or`, do not use `!`, `&&` and/or `||`

- newline: LF, not CRLF

- others: basically, follow [this style guide](https://github.com/rubocop/ruby-style-guide)

4. create a pull request to the upstream `develop` branch

Use either Japanese or English for both the title and description.

## 意見質問感想その他/Others

まずはIssueを立ててみてください。
First, try creating an issue.

## Security

セキュリティ関連の問題や脆弱性を見つけた場合は開発者に直接連絡してください。
If you find any security-related issues or vulnerabilities, please contact the developers directly.

Thank you for your contribution!
