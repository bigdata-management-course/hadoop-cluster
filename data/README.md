# Input data

Three public-domain books from Project Gutenberg (about 7 MB total):

| File | Book | Source |
|---|---|---|
| `shakespeare.txt` | The Complete Works of William Shakespeare (eBook #100) | https://www.gutenberg.org/cache/epub/100/pg100.txt |
| `moby-dick.txt` | Moby-Dick; or, The Whale, Herman Melville (eBook #2701) | https://www.gutenberg.org/cache/epub/2701/pg2701.txt |
| `pride-and-prejudice.txt` | Pride and Prejudice, Jane Austen (eBook #1342) | https://www.gutenberg.org/cache/epub/1342/pg1342.txt |

Downloaded October 2026. The Project Gutenberg header and license footer were cut
(everything outside the `*** START OF ...` / `*** END OF ...` markers) and CRLF
line endings converted to LF, so only the book text is counted:

```sh
curl -fsSL -A "Mozilla/5.0" -o pg2701.txt https://www.gutenberg.org/cache/epub/2701/pg2701.txt
awk '/^\*\*\* END OF/{exit} f{print} /^\*\*\* START OF/{f=1}' pg2701.txt | tr -d '\r' > moby-dick.txt
```
