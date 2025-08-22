from fastapi import FastAPI
from pydantic import BaseModel
from fastapi.middleware.cors import CORSMiddleware
import requests
import json
import uuid
from datetime import datetime
from typing import List, Dict, Optional
import re

app = FastAPI()
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Global state with enhanced structure
interview_sessions = {}

class ContextReq(BaseModel):
    company: str
    role: str
    interview_type: str
    max_questions: int = 5
    candidate_name: str = ""

class AnswerReq(BaseModel):
    answer: str
    session_id: str

class InterviewSession:
    def __init__(self, context: dict):
        self.session_id = str(uuid.uuid4())
        self.context = context
        self.questions = []
        self.answers = []
        self.scores = []
        self.feedbacks = []
        self.current_question = 0
        self.total_score = 0
        self.start_time = datetime.now()
        self.end_time = None
        self.is_complete = False

def call_lmstudio(messages):
    url = "http://127.0.0.1:1234/v1/chat/completions"
    body = {
        "model": "mistral-7b-instruct-v0.3",
        "messages": messages,
        "temperature": 0.7,
        "max_tokens": 800
    }
    try:
        response = requests.post(url, json=body)
        print("DEBUG raw response:", response.text)
        
        if response.status_code != 200:
            raise Exception(f"LM Studio returned status {response.status_code}: {response.text}")
        
        data = response.json()
        
        if "error" in data:
            raise Exception(f"LM Studio error: {data['error']}")
        
        if "choices" not in data or len(data["choices"]) == 0:
            raise Exception("No choices returned from LM Studio")
        
        return data["choices"][0]["message"]["content"]
    
    except Exception as e:
        print(f"Error calling LM Studio: {e}")
        return "I apologize, but I'm having trouble generating a response. Please try again."

def create_interview_prompt(context, question_number, total_questions):
    return (
        f"You are an expert interviewer at {context['company']} conducting a {context['interview_type']} "
        f"interview for the {context['role']} position. This is question {question_number} of {total_questions}. "
        f"Ask ONE professional, relevant question. Keep it clear and focused on assessing the candidate's skills."
    )

def create_evaluation_prompt(context, question, answer):
    return (
        f"As an expert interviewer for {context['role']} at {context['company']}, evaluate this {context['interview_type']} interview answer.\n\n"
        f"Question: {question}\n"
        f"Answer: {answer}\n\n"
        f"Provide a score from 1-10 and brief feedback. Format your response as:\n"
        f"Score: [number]\n"
        f"Feedback: [brief constructive feedback]\n"
        f"Focus on technical accuracy, communication clarity, and relevance to the role."
    )

def parse_evaluation(evaluation_text):
    try:
        lines = evaluation_text.strip().split('\n')
        score = 5  # default score
        feedback = "No specific feedback provided."
        
        for line in lines:
            if line.lower().startswith('score:'):
                score_text = line.split(':', 1)[1].strip()
                # Extract number from score text
                score_match = re.search(r'\d+', score_text)
                if score_match:
                    score = min(10, max(1, int(score_match.group())))
            elif line.lower().startswith('feedback:'):
                feedback = line.split(':', 1)[1].strip()
        
        return score, feedback
    except:
        return 5, "Evaluation parsing failed."

@app.post("/start")
def start_interview(req: ContextReq):
    # Create new session
    session = InterviewSession(req.dict())
    interview_sessions[session.session_id] = session
    
    # Generate first question
    interview_prompt = create_interview_prompt(session.context, 1, req.max_questions)
    
    messages = [
        {
            "role": "user", 
            "content": f"{interview_prompt}\n\nStart the {req.interview_type} interview for the {req.role} position at {req.company} with your first question."
        }
    ]
    
    first_question = call_lmstudio(messages)
    
    # Store the question
    session.questions.append({
        "number": 1,
        "text": first_question,
        "timestamp": datetime.now().isoformat()
    })
    session.current_question = 1
    
    return {
        "question": first_question,
        "question_number": 1,
        "total_questions": req.max_questions,
        "session_id": session.session_id
    }

@app.post("/answer")
def process_answer(req: AnswerReq):
    session = interview_sessions.get(req.session_id)
    if not session:
        return {"error": "Invalid session ID"}
    
    if session.is_complete:
        return {"error": "Interview already completed"}
    
    current_question = session.questions[-1]["text"]
    
    # Store the answer
    session.answers.append({
        "question_number": session.current_question,
        "text": req.answer,
        "timestamp": datetime.now().isoformat()
    })
    
    # Evaluate the answer
    evaluation_prompt = create_evaluation_prompt(session.context, current_question, req.answer)
    evaluation_messages = [{"role": "user", "content": evaluation_prompt}]
    
    evaluation_response = call_lmstudio(evaluation_messages)
    score, feedback = parse_evaluation(evaluation_response)
    
    # Store evaluation
    session.scores.append(score)
    session.feedbacks.append(feedback)
    session.total_score += score
    
    # Check if interview should end
    if session.current_question >= session.context["max_questions"]:
        session.is_complete = True
        session.end_time = datetime.now()
        
        # Calculate final results
        average_score = session.total_score / len(session.scores)
        
        return {
            "question": f"Thank you for completing the interview! Your average score is {round(average_score, 1)}/10.",
            "interview_complete": True,
            "question_number": session.current_question,
            "total_questions": session.context["max_questions"],
            "session_id": session.session_id,
            "current_score": score,
            "current_feedback": feedback,
            "final_results": {
                "total_score": session.total_score,
                "average_score": round(average_score, 1),
                "questions_answered": len(session.scores)
            }
        }
    
    # Generate next question with context
    context_messages = []
    
    # Add interview context
    interview_context = create_interview_prompt(session.context, session.current_question + 1, session.context["max_questions"])
    context_messages.append({"role": "user", "content": interview_context})
    
    # Add conversation history
    for i, (q, a) in enumerate(zip(session.questions, session.answers)):
        context_messages.append({"role": "assistant", "content": q["text"]})
        context_messages.append({"role": "user", "content": a["text"]})
    
    # Request next question
    context_messages.append({
        "role": "user", 
        "content": f"Based on the conversation, ask the next relevant question for this {session.context['interview_type']} interview."
    })
    
    next_question = call_lmstudio(context_messages)
    
    # Store next question
    session.current_question += 1
    session.questions.append({
        "number": session.current_question,
        "text": next_question,
        "timestamp": datetime.now().isoformat()
    })
    
    return {
        "question": next_question,
        "question_number": session.current_question,
        "total_questions": session.context["max_questions"],
        "session_id": session.session_id,
        "interview_complete": False,
        "current_score": score,
        "current_feedback": feedback
    }

@app.get("/results/{session_id}")
def get_results(session_id: str):
    session = interview_sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}
    
    if not session.is_complete:
        return {"error": "Interview not completed yet"}
    
    # Prepare detailed results
    detailed_results = []
    for i in range(len(session.questions)):
        if i < len(session.answers) and i < len(session.scores):
            detailed_results.append({
                "question_number": i + 1,
                "question": session.questions[i]["text"],
                "answer": session.answers[i]["text"],
                "score": session.scores[i],
                "feedback": session.feedbacks[i] if i < len(session.feedbacks) else "No feedback"
            })
    
    duration = (session.end_time - session.start_time).total_seconds() / 60  # in minutes
    average_score = session.total_score / len(session.scores) if session.scores else 0
    
    return {
        "session_id": session_id,
        "context": session.context,
        "start_time": session.start_time.isoformat(),
        "end_time": session.end_time.isoformat(),
        "duration_minutes": round(duration, 1),
        "total_score": session.total_score,
        "average_score": round(average_score, 1),
        "max_possible_score": len(session.scores) * 10,
        "percentage": round((average_score / 10) * 100, 1),
        "detailed_results": detailed_results
    }

@app.post("/save_interview/{session_id}")
def save_interview_log(session_id: str):
    session = interview_sessions.get(session_id)
    if not session:
        return {"error": "Session not found"}
    
    try:
        # Create log filename with timestamp
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"interview_log_{session_id[:8]}_{timestamp}.json"
        
        # Prepare log data
        log_data = {
            "session_id": session_id,
            "context": session.context,
            "start_time": session.start_time.isoformat(),
            "end_time": session.end_time.isoformat() if session.end_time else None,
            "is_complete": session.is_complete,
            "questions": session.questions,
            "answers": session.answers,
            "scores": session.scores,
            "feedbacks": session.feedbacks,
            "total_score": session.total_score,
            "average_score": round(session.total_score / len(session.scores), 1) if session.scores else 0
        }
        
        # Save to file
        with open(filename, 'w') as f:
            json.dump(log_data, f, indent=2, default=str)
        
        return {"message": f"Interview log saved as {filename}"}
        
    except Exception as e:
        return {"error": f"Failed to save log: {str(e)}"}

@app.get("/status")
def get_status():
    active_sessions = len([s for s in interview_sessions.values() if not s.is_complete])
    return {
        "active_sessions": active_sessions,
        "total_sessions": len(interview_sessions)
    }

@app.post("/reset")
def reset_all_sessions():
    global interview_sessions
    interview_sessions = {}
    return {"status": "All sessions reset"}