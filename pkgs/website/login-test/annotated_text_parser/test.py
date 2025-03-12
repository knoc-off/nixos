import requests
import json
import os
import time
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Get API key from environment variables
api_key = os.getenv("OPENROUTER_API_KEY")

# OpenRouter API endpoint
url = "https://openrouter.ai/api/v1/chat/completions"

headers = {
    "Authorization": f"Bearer {api_key}",
    "Content-Type": "application/json",
    "HTTP-Referer": "https://your-app-or-website.com"  # Replace with your actual website
}

def call_openrouter(messages, model="openai/gpt-4o"):
    """Call the OpenRouter API with the given messages."""
    data = {
        "model": model,
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": 4000
    }

    try:
        response = requests.post(url, headers=headers, json=data)
        response.raise_for_status()
        return response.json()["choices"][0]["message"]["content"]
    except Exception as e:
        print(f"Error calling OpenRouter API: {e}")
        if hasattr(response, 'text'):
            print(f"Response: {response.text}")
        return None

def extract_xml_content(text):
    """Extract content between <document> tags."""
    start_tag = "<document>"
    end_tag = "</document>"

    start_index = text.find(start_tag)
    end_index = text.find(end_tag)

    if start_index != -1 and end_index != -1:
        return text[start_index:end_index + len(end_tag)]
    else:
        # If tags not found, look for the content in a code block
        import re
        code_block_pattern = r"```(?:xml)?\s*(<document>.*?</document>)\s*```"
        match = re.search(code_block_pattern, text, re.DOTALL)
        if match:
            return match.group(1)
        else:
            return text  # Return the original text if no tags found

def sequential_annotation(original_essay):
    """Process an essay through all annotation stages."""
    conversation = []
    current_xml = f"<document>\n   {original_essay}\n</document>"

    # Stage 1: Initial Setup
    print("Stage 1: Initial Setup")
    conversation.append({
        "role": "system",
        "content": "You are an expert essay editor who specializes in annotating essays with XML tags to indicate corrections."
    })

    conversation.append({
        "role": "user",
        "content": f"Here is an essay that needs annotation. For now, just confirm the structure is correct:\n\n{current_xml}"
    })

    response = call_openrouter(conversation)
    print(f"Stage 1 Response:\n{response}\n")

    # Stage 2: Word-Level and Grammar Corrections
    print("Stage 2: Word-Level and Grammar Corrections")
    conversation.append({
        "role": "assistant",
        "content": response
    })

    stage2_prompt = """
    Now, analyze the text and insert corrections for word-level and grammar issues. Focus on:
    - Spelling errors
    - Grammatical errors (e.g., subject-verb agreement, verb tense)
    - Punctuation issues
    - Incorrect word forms
    - Singular/plural mismatches
    - Capitalization errors

    Rules:
    1. Use the following XML structure for corrections:
       <correction type="TYPE">
           <original>original text</original>
           <corrected>corrected text</corrected>
           <explanation>optional explanation</explanation>
       </correction>
    2. Preserve all unmodified text exactly as it appears in the original essay.
    3. Do not make stylistic or structural changes at this stage.
    4. Ensure valid XML formatting with proper nesting.

    Return the complete XML document with these corrections.
    """

    conversation.append({
        "role": "user",
        "content": stage2_prompt
    })

    response = call_openrouter(conversation)
    current_xml = extract_xml_content(response)
    print(f"Stage 2 Response:\n{current_xml}\n")

    # Stage 3: Stylistic and Tonal Corrections
    print("Stage 3: Stylistic and Tonal Corrections")
    conversation.append({
        "role": "assistant",
        "content": response
    })

    stage3_prompt = f"""
    Now, analyze the text and insert corrections for stylistic and tonal issues. Focus on:
    - Wordiness or awkward phrasing
    - Passive voice
    - Inappropriate or imprecise word usage
    - Adjusting formality to match the intended audience
    - Fixing incorrect idiomatic expressions
    - Removing unnecessary repetition

    Rules:
    1. Use the following XML structure for corrections:
       <correction type="TYPE">
           <original>original text</original>
           <corrected>corrected text</corrected>
           <explanation>optional explanation</explanation>
       </correction>
    2. Nest corrections if they overlap with word-level or grammar corrections from Stage 2.
    3. Preserve all unmodified text exactly as it appears in the original essay.
    4. Ensure valid XML formatting with proper nesting.

    Start with the current XML and add these new corrections:
    {current_xml}

    Return the complete XML document with these additional corrections.
    """

    conversation.append({
        "role": "user",
        "content": stage3_prompt
    })

    response = call_openrouter(conversation)
    current_xml = extract_xml_content(response)
    print(f"Stage 3 Response:\n{current_xml}\n")

    # Stage 4: Structural and Logical Flow Corrections
    print("Stage 4: Structural and Logical Flow Corrections")
    conversation.append({
        "role": "assistant",
        "content": response
    })

    stage4_prompt = f"""
    Now, analyze the text and insert corrections for structural and logical flow issues. Focus on:
    - Reorganizing sentences or paragraphs for clarity
    - Improving logical flow and transitions
    - Ensuring parallel structure in lists or comparisons
    - Fixing misplaced or dangling modifiers
    - Completing incomplete sentences
    - Fixing run-on sentences or comma splices

    Rules:
    1. Use the following XML structure for corrections:
       <correction type="TYPE">
           <original>original text</original>
           <corrected>corrected text</corrected>
           <explanation>optional explanation</explanation>
       </correction>
    2. Nest corrections if they overlap with word-level, grammar, or stylistic corrections from previous stages.
    3. Preserve all unmodified text exactly as it appears in the original essay.
    4. Ensure valid XML formatting with proper nesting.

    Start with the current XML and add these new corrections:
    {current_xml}

    Return the complete XML document with these additional corrections.
    """

    conversation.append({
        "role": "user",
        "content": stage4_prompt
    })

    response = call_openrouter(conversation)
    current_xml = extract_xml_content(response)
    print(f"Stage 4 Response:\n{current_xml}\n")

    # Stage 5: Final Validation
    print("Stage 5: Final Validation")
    conversation.append({
        "role": "assistant",
        "content": response
    })

    stage5_prompt = f"""
    Finally, validate the XML annotations against these requirements:
    1. All original text is preserved outside correction tags.
    2. No words are omitted, duplicated, or reordered.
    3. XML is well-formed (proper nesting/closing tags).
    4. Corrections are properly nested when overlapping.
    5. Explanations are included for non-obvious corrections.

    If any issues are found, fix them and return the corrected XML.
    If no issues are found, return the validated XML.

    Current XML:
    {current_xml}
    """

    conversation.append({
        "role": "user",
        "content": stage5_prompt
    })

    response = call_openrouter(conversation)
    final_xml = extract_xml_content(response)
    print(f"Final Validated XML:\n{final_xml}\n")

    return final_xml

# Example usage
if __name__ == "__main__":
    # Sample essay with various types of errors
    sample_essay = """
My favoritest book is "The Great Gatsby" by F. Scott Fitzgerald, who wrote it back when people wore weird hats and drove old cars. The book is about this guy Gatsby, who’s super rich and throws big, loud parties just to impress a girl named Daisy, who’s kind of fancy but also annoying. I liked it because it’s about love and dreams and how life is unfair, which is relatable. Plus, Gatsby is cool because he’s rich but also sad, so he’s deep or something.

Another reason I liked it is because it’s short, which is good since long books are boring. The author uses fancy words like "orgastic" that I don’t understand, but they make the book seem smart. The ending is sad, which is better than a happy ending because happy endings are lame and fake. Overall, it’s my favorite book because it’s about rich people, sadness, and dreams, and it makes me feel smart for reading it.
    """

    # Process the essay through all stages
    annotated_xml = sequential_annotation(sample_essay)

    # Save the result to a file
    with open("annotated_essay.xml", "w") as f:
        f.write(annotated_xml)

    print("Annotation process completed. Result saved to 'annotated_essay.xml'")

