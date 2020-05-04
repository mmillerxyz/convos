import Reactive from './Reactive';
import {debounce} from './util';
import {isISOTimeString} from './Time';
import {route} from '../store/Route';

export default class Scrollspy extends Reactive {
  constructor() {
    super();
    this.onScroll = debounce(this.onScroll.bind(this), 50);
    this.pos = 'bottom';
    this.scrollTo = this.scrollTo.bind(this);
    this.wrapper = null;
  }

  findVisibleElements(selector, limit) {
    if (!this.wrapper) return null;

    let els = [].slice.call(this.wrapper.querySelectorAll(selector), 0);
    if (!els.length) return els;

    const scrollTop = this.wrapper.scrollTop;
    let haystack = els.slice(0).map((el, i) => [i, el]);

    while (haystack.length > 1) {
      const index = Math.floor(haystack.length / 2);
      if (haystack[index][1].offsetTop < scrollTop) {
        haystack.splice(0, index);
      }
      else {
        haystack.splice(index);
      }
    }

    if (!haystack.length && els.length) haystack.push([0, els[0]]);

    const offsetHeight = this.wrapper.offsetHeight;
    const start = haystack[0][0];
    let stop = start;
    while (stop < els.length) {
      if (els[stop].offsetTop > scrollTop + offsetHeight) break;
      if (limit && stop - start >= limit) break;
      stop++;
    }

    return els.slice(start, stop);
  }

  keepPos(height) {
    if (height) this.height = height;
    if (!this.wrapper || this.onScroll.debounceTid) return;

    const selector = !route.hash ? '' : isISOTimeString(route.hash) ? '[data-ts="' + route.hash + '"]' : '#' + route.hash;
    const el = selector && document.querySelector(selector);
    console.log('[keepPos]', el ? 'el' : this.pos, this.height);

    if (el) {
      this.scrollTo(el, this.wrapper);
    }
    else if (this.pos == 'bottom') {
      this.scrollTo(this.height, this.wrapper);
    }
  }

  observe(selector) {
    if (!this.wrapper) return;

    if (!this.observer) {
      const cb = (entries) => entries.forEach(entry => this.emit('observed', entry));
      this.observer = new IntersectionObserver(cb, {rootMargin: '0px'});
    }

    this.observer.disconnect();
    const els = this.wrapper.querySelectorAll(selector);
    for (let i = 0; i < els.length; i++) this.observer.observe(els[i]);
  }

  onScroll(e) {
    if (!this.wrapper) return null;
    if (this.scrolledByCode) return delete this.scrolledByCode;

    const offsetHeight = this.wrapper.offsetHeight;
    const scrollTop = this.wrapper.scrollTop;

    this.pos
      = offsetHeight >= this.height ? 'bottom'
      : scrollTop > this.height - offsetHeight - 50 ? 'bottom'
      : scrollTop < 100 ? 'top'
      : 'middle';

    this.emit('scroll', e);
  }

  scrollTo(to, guard = 0) {
    if (guard >= 5) return; // Give up
    if (!this.wrapper) return setTimeout(() => this.scrollTo(to, guard + 1), 20);

    if (typeof to == 'number') {
      this.scrolledByCode = true;
      return (this.wrapper.scrollTop = to);
    }

    if (typeof to == 'string') {
      const el = document.querySelector(to);
      return el ? this.scrollTo(el, 0) : setTimeout(() => this.scrollTo(to, guard + 1), 20);
    }

    if (to.href && to.href.indexOf('#') != -1) {
      location.hash = to.href.replace(/.*#/, '#');
      return this.scrollTo(location.hash);
    }

    if (to.tagName) return this.scrollTo(to.offsetTop - 30); // Cannot scroll all the way to element, because of header
    if (to.preventDefault) to.preventDefault();
    if (to.target && to.target.tagName) return this.scrollTo(to.target.closest('[href]'));

    throw 'Cannot scroll to ' + to;
  }
}
