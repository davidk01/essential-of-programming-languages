# Description
`let_grammar.rb` implements most of the stuff presented in chapter 3 of "Essentials of Programming Languages" with some deviations. The deviations are
minor and are mostly changes in implementation detail because I'm using Ruby instead of Scheme so I can leverage various classes and datastructures
from Ruby. The one major thing that I haven't implemented is the nameless translator and interpreter. I plan to come back to it at some later point
after going through the book at least once.

Run the examples with
```
ruby -r'./let_grammar' -r'pp' -e 'pp LetGrammar.eval(File.read("examples/ex14"))'
```