"""
Complete RAG Pipeline using pgvector + Claude
Usage: python3 rag_pipeline.py "your question here"
"""
import sys
import psycopg2
import anthropic
from sentence_transformers import SentenceTransformer


class RAGPipeline:
    def __init__(self, db_name="postgres", model_name="all-MiniLM-L6-v2"):
        self.conn = psycopg2.connect(f"dbname={db_name} host=/tmp")
        self.cur = self.conn.cursor()
        self.embedder = SentenceTransformer(model_name)
        self.claude = anthropic.Anthropic()

    def search(self, query: str, top_k: int = 3, min_sim: float = 0.20) -> list:
        """Search pgvector for relevant documents."""
        emb = self.embedder.encode([query])[0].tolist()
        self.cur.execute("""
            SELECT content, source, 1 - (embedding <=> %s::vector) AS similarity
            FROM documents
            WHERE 1 - (embedding <=> %s::vector) > %s
            ORDER BY embedding <=> %s::vector
            LIMIT %s;
        """, (str(emb), str(emb), min_sim, str(emb), top_k))
        return self.cur.fetchall()

    def generate(self, question: str, context_docs: list) -> str:
        """Generate answer using Claude with retrieved context."""
        if not context_docs:
            return "I don't have relevant documentation to answer this question."

        context = "\n\n---\n\n".join(
            f"[Source: {src}]\n{content}"
            for content, src, sim in context_docs
        )

        msg = self.claude.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=400,
            temperature=0,
            system="""You are a PostgreSQL DBA assistant. Answer using ONLY the provided context.
Cite sources with [source: name]. Be specific and include exact commands when relevant.
If the context doesn't fully answer the question, say what's missing.""",
            messages=[{"role": "user", "content": f"Context:\n{context}\n\n---\nQuestion: {question}"}]
        )
        return msg.content[0].text

    def query(self, question: str) -> None:
        """Full RAG pipeline: search -> generate -> display."""
        print(f"\nQ: {question}")
        print("=" * 60)

        docs = self.search(question)

        print(f"\nRetrieved {len(docs)} documents:")
        for content, source, sim in docs:
            print(f"  [{sim:.4f}] {source}")

        print(f"\nAnswer:")
        answer = self.generate(question, docs)
        print(answer)
        print()

    def close(self):
        self.cur.close()
        self.conn.close()


if __name__ == "__main__":
    rag = RAGPipeline()

    if len(sys.argv) > 1:
        question = " ".join(sys.argv[1:])
        rag.query(question)
    else:
        print("RAG Pipeline Ready (type 'quit' to exit)")
        print("-" * 40)
        while True:
            q = input("\nQuestion: ").strip()
            if q.lower() in ('quit', 'exit', 'q'):
                break
            if q:
                rag.query(q)

    rag.close()
