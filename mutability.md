Use N2 (the random access serilization format) in simple forward mode for the entire file tree and contents

Allow pointers to point past the start of the current doc, they can reference previous docs

Each doc has a wrapper container that links to it's parent by caify hash and size


In the VFS, store uncommitted writes in a mutable tree, for existing files, store a content-hash of the original file so that the editor knows if a file was changed, and then not changed.

on commit, write a new document that references the old document for unchanged paths, but embeds new content for changed values

This doc wrapper might also contain custom refs for all unchanged trees and blobs so that linking to these doesn't need long pointers, but short refs instead

these refs are not simple offset pointers, but caify + path addresses.  If a particular path hasn't been updated in several commits, it will point directly to the last version that modified the path.  This way any particular path will require no more than one doc per path segment to resolve

For example, consider this site

```
VERSION-0

- www/
  - index.html* - dynamic generated HTML file, depends on files in theme/ and posts/
  - posts/* - dynamic generated folder, depends on theme and posts
  - images/
    - logo.png
    - header.png
- posts/
  - welcome/
    - index.md
    - sunrise.jpg
- theme/
  - layout.html
  - footer.html
  - sidebar.html
```

When adding a new post, there is no need to directly modify `index.html` since it's dynamic and depends on iterating over posts as part of it's generation code.  So the new version will look like:

```
VERSION-1

- www/ @VERSION-0
- posts/
  - welcome/ @VERSION-0
  - code/
    - index.md
- theme/ @VERSION-0
```

Since the paths are also unchanged we can simply store the doc id when referencing a previous document.




We can use n2 refs to compactly store these links inline.

Each revision has commit-like metadata:

- date
- author
- signature
- message
- parent(s)
  - a list of caify hashes for the parent revision(s)
  - these can include lightweight metadata about where to find the hashes if desired
- refs
  - a list of ref pairs (parent index + byte offset into that parent)
- content
  - the N2 body of this revision and it's new changes
