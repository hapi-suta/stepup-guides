# Concepts 5.3: Natural Language Processing (NLP)

**Tier 5 - Deep learning and NLP.** Teaching reference. A model does math on numbers, but a document is text. **NLP** (Natural Language Processing) is the set of techniques that turns messy human text into numbers a model can learn from, and turns model outputs back into useful answers. This doc covers the classic NLP toolkit you use in the BUILD document classifier: cleaning, tokenizing, TF-IDF features, classification, and the named-entity and topic ideas on top.

**Who this is for:** DBAs who finished Concepts 5.1 and 5.2. No linguistics background assumed.

**Run the snippets:** on your **lab server**, as **ec2-user**, start Python:

```bash
python3.12
```

`exit()` to leave. Where a snippet needs a library, the BUILD shows the install command. We keep every model and dataset tiny so it runs on CPU in seconds.

---

## 1. Why text is hard

Text has no fixed shape. Documents differ in length, spelling, punctuation, case, and language. "Invoice", "invoice", "INVOICE", and "facture" (French) may all mean the same thing to a human. Our job in NLP is to normalize this mess into consistent numbers. The BUILD classifier handles English AND French, so normalization matters double.

---

## 2. Text cleaning

**Text cleaning** (or normalization) is the first step: make text consistent before you do anything else. Typical operations:

- **Lowercasing**: so "Invoice" and "invoice" count as the same word.
- **Removing punctuation and extra whitespace**: so "invoice." and "invoice" match.
- **Stripping non-text noise**: HTML tags, weird symbols, page numbers.

```python
import re
raw = "  Invoice #4471 -- PAID in full!!  "
clean = re.sub(r"[^a-z0-9 ]", " ", raw.lower())   # keep letters/digits/spaces
clean = re.sub(r"\s+", " ", clean).strip()        # collapse whitespace
clean
```

Expected output:

```
'invoice 4471 paid in full'
```

Cleaning is unglamorous but it decides your accuracy. Clean the same way at training AND at prediction time - a mismatch silently wrecks accuracy (that is the SURVIVE "tokenizer-mismatch" scenario).

---

## 3. Tokenization

**Tokenization** splits cleaned text into pieces called **tokens** - usually words. A model works on tokens, not raw strings.

```python
text = "invoice 4471 paid in full"
tokens = text.split()
tokens
```

Expected output:

```
['invoice', '4471', 'paid', 'in', 'full']
```

Real tokenizers are smarter than `split()` (they handle contractions, French accents, and subwords), but the idea is the same: text becomes a list of tokens. Transformers (Concepts 5.4) use **subword** tokens so they never hit an unknown word, but for classic NLP, word tokens are enough.

---

## 4. Stemming and lemmatization

Words have forms: "run", "runs", "running", "ran". To a bag-of-words model these look like four different words unless you collapse them.

- **Stemming** chops word endings with crude rules: "running" -> "run", "invoices" -> "invoic". Fast, but the result is not always a real word.
- **Lemmatization** maps a word to its dictionary base form using real language knowledge: "ran" -> "run", "better" -> "good". More accurate, a bit slower. (The "better" -> "good" case only works when the lemmatizer is told the word is an adjective - lemmatizers use part-of-speech information, and without it "better" is often left unchanged.)

Both shrink your vocabulary so related forms share one feature. For a bilingual classifier you would apply the right-language rules per document. Our BUILD keeps it simple and skips aggressive stemming, but you should know the terms.

---

## 5. Stop words

**Stop words** are extremely common words that carry little meaning on their own: "the", "a", "is", "and" in English; "le", "la", "et", "de" in French. Removing them lets the model focus on the words that actually distinguish documents.

```python
stop_words = {"the", "a", "is", "and", "in", "to", "of"}
tokens = ["the", "invoice", "is", "in", "full"]
kept = [t for t in tokens if t not in stop_words]
kept
```

Expected output:

```
['invoice', 'full']
```

For the bilingual BUILD you supply BOTH an English and a French stop-word list. Miss the French list and French documents keep all their "le/la/de" noise.

---

## 6. Bag of words

The **bag of words** model represents a document as a count of how many times each vocabulary word appears, ignoring order. "invoice paid invoice" becomes `{invoice: 2, paid: 1}`. It throws away word order but is astonishingly effective for classification, because the mere presence of "invoice", "resume", or "contract" strongly signals the document type.

The output is a **vector**: one number per vocabulary word. A vocabulary of 5,000 words gives a 5,000-number vector per document. That vector is the feature input to a model.

---

## 7. TF-IDF: bag of words, but smarter

Plain counts over-weight common words. **TF-IDF** (Term Frequency times Inverse Document Frequency) fixes that by weighting each word by how *distinctive* it is:

- **Term Frequency (TF)**: how often the word appears in this document. Frequent-here = important-here.
- **Inverse Document Frequency (IDF)**: how rare the word is across ALL documents. A word in every document (like "date") gets a low weight; a word in only invoices (like "remittance") gets a high weight.

TF-IDF gives high scores to words that are frequent in one document but rare overall - exactly the words that identify a document's type. It is the classic, CPU-friendly feature representation, and it is what the BUILD feeds into the tiny PyTorch network. Because both English and French words end up as columns in the same TF-IDF vocabulary, one model can handle both languages.

---

## 8. Text classification

**Text classification** assigns a document to one of several categories - the BUILD's whole job (invoice vs resume vs contract, in English or French). The pipeline is:

1. Clean the text.
2. Turn it into a TF-IDF vector.
3. Feed the vector to a trained classifier (our tiny PyTorch net).
4. The output layer produces a probability per class (softmax); the highest is the prediction, and its probability is the **confidence score**.

Confidence scores let you route low-confidence documents to a human - the human-correction loop in USE.

---

## 9. Sentiment analysis

**Sentiment analysis** is text classification where the classes are feelings: positive, negative, neutral. "The product is fantastic" -> positive; "terrible support, never again" -> negative. Same machinery as document classification, different labels. It is one of the most requested consulting builds (analyzing reviews, support tickets, survey text). If you can build the document classifier, you can build a sentiment analyzer by swapping the labels - which is exactly the USE "swap-classifier-head" exercise.

---

## 10. Named Entity Recognition (NER)

**Named Entity Recognition** finds and labels the specific things inside text: people, organizations, locations, dates, money amounts. In "Acme Corp paid $4,471 on March 3", NER would tag "Acme Corp" as an ORGANIZATION, "$4,471" as MONEY, "March 3" as a DATE.

For a document-processing consultant, NER extracts the key fields (vendor, amount, date) from a classified document. The BUILD includes a lightweight, rule-and-pattern NER step to pull out entities like money amounts and dates - enough to be useful without a heavy model. A production system might use a dedicated NER model, but the concept and the value are the same.

---

## 11. Topic modeling

**Topic modeling** is unsupervised: instead of you providing labels, the algorithm discovers clusters of words that tend to appear together and calls each cluster a "topic." Feed it thousands of documents and it might surface a "billing" topic (invoice, payment, due, amount) and a "hiring" topic (resume, experience, skills, candidate). It is useful for exploring a big pile of unlabeled documents before you decide what to classify. Common methods: LDA (Latent Dirichlet Allocation) and, more modern, clustering document embeddings. You do not build one in this tier, but you should be able to explain it: classification needs labels, topic modeling finds structure without them.

---

## 12. Sequence models: when word order matters

Bag of words and TF-IDF throw away order, which is fine for "what type of document is this?" But some tasks need order: "the movie was not good" means the opposite of "good", and order is the only clue. **Sequence models** read tokens in order and keep a running memory:

- **RNN / LSTM / GRU**: older sequence models that process tokens one at a time, carrying a hidden memory forward. They handle order but struggle with long documents (they forget the start).
- **Transformers** (Concepts 5.4): the modern answer. They look at all tokens at once using attention, so they capture long-range order without forgetting. Transformers replaced RNNs for almost everything.

The BUILD deliberately uses order-free TF-IDF because it is CPU-friendly, fast, and plenty accurate for document typing. Sequence models and transformers are where you go when meaning depends on order and you have a GPU. **This is a spot a real project reaches for a GPU** - training or fine-tuning a sequence/transformer model on real data.

---

## Takeaways

- NLP turns messy text into consistent numbers. Clean the SAME way at training and prediction, or accuracy silently collapses.
- Pipeline: clean -> tokenize -> (optional stem/lemmatize, remove stop words) -> TF-IDF vector -> classifier.
- TF-IDF weights words by how distinctive they are; it is the CPU-friendly feature representation the BUILD uses, and it holds English and French in one vocabulary.
- Text classification, sentiment analysis, and NER all reuse the same core; only the labels or the output step change.
- Topic modeling is unsupervised structure-finding; classification needs labels.
- Bag of words ignores order; sequence models and transformers keep it - reach for those (and a GPU) when meaning depends on order.

---

## References

Authoritative sources used to fact-check the concepts in this document.

- TF-IDF, bag of words, and stop words - scikit-learn text feature extraction (`TfidfVectorizer`, `CountVectorizer`): https://scikit-learn.org/stable/modules/feature_extraction.html
- Stemming vs lemmatization: https://www.ibm.com/think/topics/stemming-lemmatization
- Named Entity Recognition entity classes (person, organization, location, date, money, etc.) - Stanford NER: https://nlp.stanford.edu/software/CRF-NER.html
- Topic modeling / Latent Dirichlet Allocation (LDA): https://www.jmlr.org/papers/v3/blei03a.html
- RNN / LSTM / GRU vs transformers (sequence models and long-range dependencies): https://huggingface.co/docs/transformers/en/model_summary
- Subword tokenization used by modern transformers: https://huggingface.co/docs/transformers/en/tokenizer_summary

Prof. Happy (SUTA Labs)
