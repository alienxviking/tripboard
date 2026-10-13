import { useEffect, useState } from 'react'
import { api } from './api.js'

const EMPTY = { destination: '', start_date: '', end_date: '', budget: '', status: 'planned' }
const NEXT = { planned: 'booked', booked: 'done', done: 'planned' }

export default function App() {
  const [trips, setTrips] = useState([])
  const [form, setForm] = useState(EMPTY)
  const [info, setInfo] = useState(null)
  const [error, setError] = useState('')

  const load = () => api.list().then(setTrips).catch((e) => setError(e.message))

  useEffect(() => {
    load()
    api.info().then(setInfo).catch(() => {})
  }, [])

  const submit = async (e) => {
    e.preventDefault()
    setError('')
    try {
      await api.create({ ...form, budget: Number(form.budget || 0) })
      setForm(EMPTY)
      load()
    } catch (err) {
      setError(err.message)
    }
  }

  const advance = async (t) => {
    await api.update(t.id, { ...t, status: NEXT[t.status] })
    load()
  }

  const remove = async (t) => {
    await api.remove(t.id)
    load()
  }

  const total = trips.reduce((sum, t) => sum + Number(t.budget), 0)

  return (
    <main>
      <header>
        <h1>TripBoard</h1>
        <p>Plan trips, track budgets. {info && <span className="tag">{info.environment} · {info.version}</span>}</p>
      </header>

      <form onSubmit={submit} className="card">
        <input placeholder="Destination" value={form.destination} onChange={(e) => setForm({ ...form, destination: e.target.value })} required />
        <input type="date" value={form.start_date} onChange={(e) => setForm({ ...form, start_date: e.target.value })} required />
        <input type="date" value={form.end_date} onChange={(e) => setForm({ ...form, end_date: e.target.value })} required />
        <input type="number" min="0" placeholder="Budget (INR)" value={form.budget} onChange={(e) => setForm({ ...form, budget: e.target.value })} />
        <button type="submit">Add trip</button>
      </form>
      {error && <p className="error">{error}</p>}

      <section className="card">
        <div className="summary">
          <span>{trips.length} trips</span>
          <span>Total budget: ₹{total.toLocaleString('en-IN')}</span>
        </div>
        <table>
          <thead>
            <tr><th>Destination</th><th>Dates</th><th>Budget</th><th>Status</th><th></th></tr>
          </thead>
          <tbody>
            {trips.map((t) => (
              <tr key={t.id}>
                <td>{t.destination}</td>
                <td>{t.start_date} → {t.end_date}</td>
                <td>₹{Number(t.budget).toLocaleString('en-IN')}</td>
                <td><button className={`status ${t.status}`} onClick={() => advance(t)} title="click to change">{t.status}</button></td>
                <td><button className="link" onClick={() => remove(t)}>delete</button></td>
              </tr>
            ))}
            {trips.length === 0 && <tr><td colSpan="5" className="empty">No trips yet</td></tr>}
          </tbody>
        </table>
      </section>
    </main>
  )
}
