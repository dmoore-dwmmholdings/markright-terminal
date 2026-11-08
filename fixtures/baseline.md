# Markdown baseline fixture

A paragraph with *emphasis*, **strong**, ~~struck~~, [link](./notes.md), ![image alt](./figure.png), <https://example.com> and escaped \*literal\*.

> Quoted **content**.

1. Ordered
2. List

- [x] Complete
- [ ] Pending

| Register | Width |
| :--- | ---: |
| CONTROL | 64 |

---

```js
const text = '::include{src="must-stay-code"}';
```

    ::include{src="indented-code"}

::future{preserve="source"}

<script>mustNeverExecute()</script>
