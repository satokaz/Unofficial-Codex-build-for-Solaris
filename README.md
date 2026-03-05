# Unofficial-Codex-build-for-Solaris
This repository provides an unofficial Solaris build of Codex.

<img width="692" height="761" alt="image" src="https://github.com/user-attachments/assets/e55fbd58-ccba-4595-a0cc-e634c671ebdf" />


`scripts/bootstrap-solaris.sh` は Oracle Solaris 11.4 環境で [openai/codex](https://github.com/openai/codex) をビルドするために必要な依存関係を local vendoring し、Solaris 向けの差分パッチを適用するユーティリティです。

## スクリプトは以下を実施

- `codex-rs/third_party/` 以下に必要な crate (`tree-sitter`、`crossterm`、`fs4`、`daemonize`、`nix`) を crates.io からダウンロードして展開
- `patches/` ディレクトリにある Solaris 用 patch を各 crate やリポジトリ本体に適用

ベース: commit b4cb989563e68639c2bdc748c20c965ba1d830ea (HEAD -> main, origin/main, origin/HEAD)
        Date:   Thu Mar 5 00:55:12 2026 -0800

## 以下のツールを用意してください　（ pkg は何が必要で足りているのかわからず。ご自身で補完をお願いいたします)

* pkg install gcc-15 gnu-make pkgconfig git gnu-patch gnu-tar curl
* Rust[Rust 1.93.1](https://forge.rust-lang.org/infra/other-installation-methods.

## ビルド手順

1. ビルドに必要なツールを準備
2. git clone https://github.com/openai/codex.git
3. codex リポジトリのルートで `solaris-bootstrap.tar.gz` を展開
4. `bootstrap-solaris.sh` を実行 (※ 要ネットワーク接続)

   ```bash
   ./scripts/bootstrap-solaris.sh
   ```

5. スクリプトは `codex-rs/third_party/` 配下に vendored crate をダウンロードおよび展開し、ログに `[PATCH]` や `[DL ]` などのステップを出力します。エラーが発生した場合はメッセージに従って必要なツールや権限を整備してください。
6. 正常終了すると `codex-rs/target/release/codex-apply-patch` (`apply-patch` コマンド)が生成され、 `codex-rs/third_party/` の vendored crate が調整されます。
7. `cargo build --release` でビルドを開始します
8. `codex-rs/target/release` に `codex` binary が生成されます

Finished が出れば build 完了です。
    ```
    Finished `release` profile [optimized] target(s) in 36m 25s
    ```
  - Intel(r) Xeon(r) Platinum 8358 CPU @ 2.60GHz で 36分程度。
  - Intel(r) Core(tm) i5-4308U CPU @ 2.80GHz で 80分程度。
    
## その他
* [ochyai/vibe-local](https://github.com/ochyai/vibe-local) と [satokaz/fake-ollama](https://github.com/satokaz/fake-ollama) と [BerriAI/litellm](https://github.com/BerriAI/litellm) と [GitHub Copilot](https://github.com/features/copilot) サービスに感謝
* 本ビルドスクリプトおよびビルドされたバイナリは実験的なものです。動作の保証はありません。
* サンプルバイナリについても動作の保証はありません。
